import com.jonwohl.*;
import gab.opencv.*;
import processing.video.*;
import processing.serial.*;
import cc.arduino.*;
import java.awt.Rectangle;

Arduino arduino;
int buttonPin = 4;
int potPin = 0;

Attention attention;
PImage src, dst, out;
OpenCV opencv;

int displayW = 1024;
int displayH = 768;

int ballHeight = 80;

Capture cam;
int camW = 320;
int camH = 240;
int camFR = 30;

float screenRatio = 1.3333333;

PVector resizeRatio = new PVector(displayW / camW, displayH / camH);

int paddleW = 150;
int paddleH = 30;
int paddleFloatDist = 60;
int ballOffset = (paddleFloatDist + paddleH + ballHeight/2 - 30);

// points for each corner of the screen, for convenience
PVector tl = new PVector(0,0);
PVector tr = new PVector(displayW, 0);
PVector br = new PVector(displayW, displayH - ballOffset);
PVector bl = new PVector(0, displayH - ballOffset);

// draw frame rate
int frameRate = 30;


// how many seconds into the future to anticipate -- read from analog pin 0
float anticipation = 0;

// the radius of the future ghosts, set from the bounding box of the contour 
float ghostRad;

// how many frames between each future 'ghosted' ball?
int framesPerGhost = 6;

// how many bounces in the future to anticipate
int futureBounces = 3;

// Lists to store the position and velocity history -- these are used to calculate current velocity
// and anticipate future position (based on average velocity)
boolean sampling = true;
ArrayList<PVector> pSamples;
ArrayList<PVector> vSamples;

// number of frames to sample -- average velocity over this many frames determines future prediction
int frameHistory = 5;
int sampleEvery = 30;

// whether or not to invert the thresholded image -- press 'i' to toggle
boolean invert = false;

boolean debug = false;

// position and velocity of the found contour (the ball)
PVector curPos = new PVector();
PVector curVel = new PVector();
PVector avgVel = new PVector();

// the position at the end of the predicted future
PVector anticipatedPos = new PVector();

// position of the paddle
PVector curPaddlePos;

// operating system
String os;

// A list of all the contours found by OpenCV
ArrayList<Contour> contours;

boolean buttonDown = false;

void setup() {
  String os=System.getProperty("os.name");
  //println(os);
  
  size(displayW, displayH);
  frameRate(frameRate);
  
  String[] ards = Arduino.list();
  //print(ards);
  
  // for Mac
  // arduino = new Arduino(this, ards[ards.length - 1], 57600);
  
  // for Odroid
  arduino = new Arduino(this, ards[0], 57600);
  arduino.pinMode(4, Arduino.INPUT);
  
  /*
  String[] cameras = Capture.list();
  
  //println("Available cameras:");
  for (int i = 0; i < cameras.length; i++) {
    //println(cameras[i]);
  }
  */
  
  pSamples = new ArrayList<PVector>();
  vSamples = new ArrayList<PVector>();
  
  // cam = new Capture(this, camW, camH);
  cam = new Capture(this, camW, camH, "/dev/video1", 30);
  cam.start();
  
  // instantiate focus passing an initial input image
  attention = new Attention(this, cam);
  out = attention.focus(cam, cam.width, cam.height);
  
  opencv = new OpenCV(this, out);
  
  curPaddlePos = new PVector(width/2, height - paddleH - 20);
}

void draw() {
  background(0);
  noCursor();
  // show attention view on buttonpress
  if (arduino.digitalRead(buttonPin) == Arduino.HIGH){
    buttonDown = true; 
  } else {
    buttonDown = false;
  }
  
  if (cam.available()) { 
    // Reads the new frame
    cam.read();
  }
  
  // warp the selected region on the input image (cam) to an output image of width x height
  out = attention.focus(cam, cam.width, cam.height);
  float thresh = map(arduino.analogRead(potPin), 0, 1024, 0, 255);
  redThreshold(out, thresh);
  if (invert) {
    out.filter(INVERT);
  }
  
  opencv.loadImage(out);
  
  dst = opencv.getOutput();
  
  contours = opencv.findContours();
  
  if (debug) {
    image(dst, 0, 0); //<>//
  }
  // focus on only the biggest contour
  if (contours.size() > 0) {
    Contour contour = contours.get(0);
    
    ArrayList<PVector> points = contour.getPolygonApproximation().getPoints();
    Rectangle bb = contour.getBoundingBox();
    ghostRad = bb.width;
    
    PVector centroid = calculateCentroid(points);

    // for TESTING ONLY!
//    PVector centroid = new PVector(mouseX, mouseY);
    
    // draw the centroid, justforthehellavit.
//    fill(255, 0, 0);
//    ellipse(centroid.x, centroid.y, 10, 10);
    
    curPos.set(centroid);
    
    // TODO: maybe some flag here, this only needs to happen once
//    anticipatedPos.set(curPos);
    
    if (sampling) {
      // add the new position sample
      if (frameCount % sampleEvery == 0) {
        pSamples.add(0, centroid);
        // limit the size of the samples list
        if(pSamples.size() > frameHistory) {
          pSamples.remove(pSamples.size() - 1);
        }
      }
      
      // calculate new velocity
      if (pSamples.size() > 1) {
        PVector p0 = new PVector();
        p0.set(pSamples.get(0));
        PVector p1 = new PVector();
        p1.set(pSamples.get(1));
        p0.sub(p1);
        
        // set current vel and push it onto the array
        curVel.set(p0);
        vSamples.add(0, p0);
        
        // limit the size of the samples list
        if(vSamples.size() > frameHistory) {
          vSamples.remove(vSamples.size() - 1);
        }
        
          // calculate average velocity vector
        avgVel.set(0,0);
        for (PVector v : vSamples) {
          avgVel.add(v);
        }
        avgVel.div(vSamples.size());
      
        //  drawVelocity();
        
        drawAnticipationB();
        
        noStroke();
          
        
        
        drawPaddle();
      }
    }
  }
 
}

void keyPressed() {
  
  if (key == 'f' || key == 'F') {
    frame.setSize(displayWidth, displayHeight);
  }
  
  // start/stop sampling
  if (key == 't' || key == 'T') {
    sampling = !sampling;
  }
  
  // do or don't invert input
  if (key == 'i' || key == 'I') {
    invert = !invert;
  }
  
  if (key == 'D' || key == 'd'){
    debug = !debug;
  }
  
  // adjust anticipation -- also hooked up to arduino analog 0
  if (keyCode == UP) {
    if (anticipation < 2) {
      anticipation += 0.1;
    }
  } 
  if (keyCode == DOWN) {
    if (anticipation > 0) {
      anticipation -= 0.1; 
    }
  } 
}

// draw the velocity vector
void drawVelocity() {
  stroke(0, 255, 0);
  PVector drawnVel = new PVector();
  drawnVel.set(avgVel);
  drawnVel.mult(10);
  line(curPos.x, curPos.y, curPos.x + drawnVel.x, curPos.y + drawnVel.y);
//  line(curPos.x, curPos.y, curPos.x + curVel.x, curPos.y + curVel.y);
}

void redThreshold(PImage img, float thresh){
 img.loadPixels();
 int numPix = 0;
 for (int i=0; i < img.pixels.length; i++){
   if (red(img.pixels[i]) > thresh){
     img.pixels[i] = color(255, 255, 255);
   } else {
     img.pixels[i] = color(0,0,0);
   }
 }
 img.updatePixels();
}


// draw the Anticipation -- uses the average velocity to draw the future position of the ball
// every [framesPerGhost] frames up to [anticipation] seconds.
void drawAnticipation() {
  // temp velocity vector
  PVector tV = new PVector();
  tV.set(avgVel);
  PVector nextP = new PVector();
  nextP.set(curPos);
  
  
  fill(255,255,255,50);
  noStroke();
  
  int numFrames = floor(frameRate * anticipation);
  
  for (int i = 0; i < numFrames; i++) {
    nextP.add(tV);
  
    if (nextP.x < 0) {
      nextP.x = -nextP.x;
      tV.x = -tV.x;
    }
    
    if (nextP.x > width) {
      nextP.x = width-(nextP.x-width);
      tV.x = -tV.x;
    }
    
    if (nextP.y < 0) {
      nextP.y = -nextP.y;
      tV.y = -tV.y;
    }
    
    // here we may want to use height - [paddle height], if we want the paddle
    // to be a little smarter...?
    if (nextP.y > height) {
      nextP.y = height-(nextP.y-height);
      tV.y = -tV.y;
    }
    
    if (i % framesPerGhost == 0) {
      ellipse(nextP.x,nextP.y,ghostRad,ghostRad);      
    }

  }
  
  anticipatedPos.x = nextP.x * resizeRatio.x;
  anticipatedPos.y = nextP.y * resizeRatio.y;
}

// draw the paddle
void drawPaddle() {
  fill(255,255,255,255);
  PVector targetPos = new PVector();
  targetPos.set(anticipatedPos);
  if (targetPos.x != targetPos.x) {
    targetPos.x = displayW/2;
    targetPos.y = displayH/2;
  }
  //println("targetPos:" + targetPos);
  
  // how much lag to add to the paddle
  int lagDivider = 20;
  
  PVector nextPaddlePos = new PVector(curPaddlePos.x + (targetPos.x - curPaddlePos.x)/lagDivider, curPaddlePos.y);
  
  rect(nextPaddlePos.x - paddleW/2, height - paddleFloatDist - paddleH/2, paddleW, paddleH);
  
  curPaddlePos.set(nextPaddlePos);
}


PVector calculateCentroid(ArrayList<PVector> points) {
  ArrayList<Float> x = new ArrayList<Float>();
  ArrayList<Float> y = new ArrayList<Float>();
  for(PVector point : points) {
    x.add(point.x);
    y.add(point.y); 
  }
  float xTemp = findAverage(x);
  float yTemp = findAverage(y);
  PVector cen = new PVector(xTemp,yTemp);
  return cen;
   
}

float findAverage(ArrayList<Float> vals) {
  float numElements = vals.size();
  float sum = 0;
  for (int i=0; i< numElements; i++) {
    sum += vals.get(i);
  }
  return sum/numElements;
}

// draw a number of bounce anticipations ahead based on current velocity
void drawAnticipationB() {
  fill(0, 255, 0);
  stroke(0, 255, 0);
  PVector tP = new PVector();
  PVector tV = new PVector();
  tP.set(curPos.x*resizeRatio.x, curPos.y*resizeRatio.y);
  tV.set(avgVel);
  if (buttonDown) {
    ellipse(tP.x, tP.y, ballHeight, ballHeight*screenRatio);
  }
  for (int i = 0; i < futureBounces; i++) {
    PVector intSec = calculateNextIntersectionPoint(tP, tV);
    if (buttonDown) {
      ellipse(intSec.x, intSec.y, 30, 30*screenRatio);
      line(tP.x, tP.y, intSec.x, intSec.y);
    }
    tP.set(intSec);
    if (intSec.y == displayH) {
      break;
    }
    if (intSec.x == displayW || intSec.x == 0) {
      tV.x = -tV.x;
    }
    if (intSec.y == displayH || intSec.y == 0) {
      tV.y = -tV.y;     
    }
  }
  anticipatedPos.set(tP);
  
  //println(anticipatedPos);
}

PVector calculateNextIntersectionPoint(PVector curPos, PVector avgVel) {
  PVector intSec;
  PVector posPlusVel = PVector.add(curPos,avgVel);
  if(avgVel.x > 0) {
     // going right, check right side
     intSec = findIntersection(curPos, posPlusVel, tr, br);
     if (intSec.y > displayH - ballOffset) {
       // will hit the floor, check bottom intersection
       intSec = findIntersection(curPos, posPlusVel, bl, br);
     } else if(intSec.y < 0) {
       // will hit the top
       intSec = findIntersection(curPos, posPlusVel, tl, tr);
       
     }
  } else {
    // going left, check left side
    intSec = findIntersection(curPos, posPlusVel, tl, bl);
    if (intSec.y > displayH - ballOffset) {
       // will hit the floor, check bottom intersection
       intSec = findIntersection(curPos, posPlusVel, bl, br);
     } else if(intSec.y < 0) {
       // will hit the top
       intSec = findIntersection(curPos, posPlusVel, tl, tr);
     }
  }
  return intSec;
}

// http://en.wikipedia.org/wiki/Line%E2%80%93line_intersection#Given_two_points_on_each_line
// p1 and p2 define first line, p3 and p4 define second line
PVector findIntersection(PVector p1, PVector p2, PVector p3, PVector p4) {
  PVector intersection = new PVector();
  
  intersection.x = ((p1.x*p2.y - p1.y*p2.x) * (p3.x - p4.x) - (p1.x - p2.x) * (p3.x*p4.y - p3.y*p4.x)) / ((p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x));
  intersection.y = ((p1.x*p2.y - p1.y*p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x*p4.y - p3.y*p4.x)) / ((p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x));
  
  return intersection;
}
