import com.jonwohl.*;
import gab.opencv.*;
import processing.video.*;
import processing.serial.*;
import cc.arduino.*;
import java.awt.Rectangle;

Arduino arduino;
Attention attention;
PImage src, dst, out;
OpenCV opencv;

Capture cam;

int camW = 640;
int camH = 480;

int paddleW = 150;
int paddleH = 20;

// draw frame rate
int frameRate = 30;


// how many seconds into the future to anticipate -- read from analog pin 0
float anticipation = 1;

// the radius of the future ghosts, set from the bounding box of the contour 
float ghostRad;

// how many frames between each future 'ghosted' ball?
int framesPerGhost = 6;

// Lists to store the position and velocity history -- these are used to calculate current velocity
// and anticipate future position (based on average velocity)
boolean sampling = false;
ArrayList<PVector> pSamples;
ArrayList<PVector> vSamples;
// number of frames to sample -- average velocity over this many frames determines future prediction
int frameHistory = 6;


// whether or not to invert the thresholded image -- press 'i' to toggle
boolean invert = false;

// position and velocity of the found contour (the ball)
PVector curPos = new PVector();
PVector curVel = new PVector();
PVector avgVel = new PVector();
// the position at the end of the predicted future
PVector anticipatedPos = new PVector();

// position of the paddle
PVector curPaddlePos;

// A list of all the contours found by OpenCV
ArrayList<Contour> contours;

void setup() {
  //  size(displayWidth, displayHeight);
  size(camW, camH);
  frame.setResizable(true);
  frameRate(frameRate);
  
  println(Arduino.list());
//  arduino = new Arduino(this, "/dev/tty.usbmodemfa131", 57600);
  
  String[] cameras = Capture.list();
  
  println("Available cameras:");
  for (int i = 0; i < cameras.length; i++) {
    println(cameras[i]);
  }
  
  pSamples = new ArrayList<PVector>();
  vSamples = new ArrayList<PVector>();
  
  cam = new Capture(this, 640, 480);
//  cam = new Capture(this, 640, 480, "Sirius USB2.0 Camera", 30);
  cam.start();
  
  // instantiate focus passing an initial input image
  attention = new Attention(this, cam);
  out = attention.focus(cam, width, height);
  
  opencv = new OpenCV(this, out);
  
  curPaddlePos = new PVector(width/2, height - paddleH - 20);
}

void draw() {
//  anticipation = map(arduino.analogRead(0), 0, 1024, 0, 2);
  println("anticipation: " + anticipation);
  
  if (cam.available()) { 
    // Reads the new frame
    cam.read();
  }
  
  // warp the selected region on the input image (cam) to an output image of width x height
  out = attention.focus(cam, width, height);
  float thresh = map(mouseY, 0, height, 0, 1);
  out.filter(THRESHOLD, thresh);
  if (invert) {
    out.filter(INVERT);
  }
  
  opencv.loadImage(out);
  
//  opencv.gray();
//  
//  opencv.threshold(int(thresh));
//  
//  
  
  dst = opencv.getOutput();
  
  contours = opencv.findContours();
  
  image(dst, 0, 0); //<>//

  // focus on only the biggest contour
  if (contours.size() > 0) {
    Contour contour = contours.get(0);
    
    ArrayList<PVector> points = contour.getPolygonApproximation().getPoints();
    Rectangle bb = contour.getBoundingBox();
    ghostRad = bb.width;
    
    PVector centroid = calculateCentroid(points);
    
    // draw the centroid, justforthehellavit.
//    fill(255, 0, 0);
//    ellipse(centroid.x, centroid.y, 10, 10);
    
    curPos.set(centroid);
    
    // TODO: maybe some flag here, this only needs to happen once
//    anticipatedPos.set(curPos);
    
    if (sampling) {
      // add the new position sample
      pSamples.add(0, centroid);
      // limit the size of the samples list
      if(pSamples.size() > frameHistory) {
        pSamples.remove(pSamples.size() - 1);
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
        drawAnticipation();
      //  println("Average vel: " + avgVel.toString());
      //  println("Current vel: " + curVel.toString());
        
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
  
  anticipatedPos.set(nextP);
//  println(anticipatedPos);
  
}

// draw the paddle
void drawPaddle() {
  fill(255,255,255,255);
  PVector targetPos = new PVector();
  targetPos.set(anticipatedPos);
//  println("targetPos: " + targetPos);
//  println("curPaddlePos: " + curPaddlePos);
  
  // how much lag to add to the paddle
  int lagDivider = 5;
  
  PVector nextPaddlePos = new PVector(curPaddlePos.x + (targetPos.x - curPaddlePos.x)/lagDivider, curPaddlePos.y);
  
  rect(nextPaddlePos.x - paddleW/2, height - paddleH*2, paddleW, paddleH);
  
  println("nextPaddlePos: " + nextPaddlePos);
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


//boolean sketchFullScreen() {
//  return true;
//}
