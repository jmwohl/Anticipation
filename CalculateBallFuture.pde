import com.jonwohl.*;
import gab.opencv.*;
import processing.video.*;

Attention attention;
PImage src, dst, out;
OpenCV opencv;

Capture cam;

int camW = 640;
int camH = 480;

int paddleW = 150;
int paddleH = 20;

// calculate trajectory based on current frame and how many frames back?
int frameHistory = 30;

// how many frames into the future to project?
int projection = 10;

boolean sampling = false;
ArrayList<PVector> pSamples;
ArrayList<PVector> vSamples;

boolean invert = false;

//PVector samples[];

int frameCounter = 0;

PVector curPos = new PVector();
PVector curVel = new PVector();
PVector avgVel = new PVector();
float velMag;

ArrayList<Contour> contours;

void setup() {
  //  size(displayWidth, displayHeight);
  size(camW, camH);
  frame.setResizable(true);
  frameRate(30);
  
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
}

void draw() {

  if (cam.available()) { 
    // Reads the new frame
    cam.read();
  }
  
  // warp the selected region on the input image (cam) to an output image of width x height
  out = attention.focus(cam, width, height);
  
  opencv.loadImage(out);
  
  opencv.gray();
  float thresh = map(mouseY, 0, height, 0, 255);
  opencv.threshold(int(thresh));
  
  if (invert) {
    opencv.invert();
  }
  
  dst = opencv.getOutput();
  
  contours = opencv.findContours();
  
  image(dst, 0, 0); //<>//

  // focus on only the biggest contour
  if (contours.size() > 0) {
    Contour contour = contours.get(0);
    
    ArrayList<PVector> points = contour.getPolygonApproximation().getPoints();
    PVector centroid = calculateCentroid(points);
    
    // draw the centroid, justforthehellavit.
    fill(255, 0, 0);
    ellipse(centroid.x, centroid.y, 10, 10);
    
    curPos.set(centroid);
    
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
      }
    }
  }
  
  // calculate average velocity vector
  avgVel.set(0,0);
  for (PVector v : vSamples) {
    avgVel.add(v);
  }
  avgVel.div(vSamples.size());
  drawVelocity();
  println("Average vel: " + avgVel.toString());
  println("Current vel: " + curVel.toString());
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

// draw the velocity vector
void drawPaddle() {
  fill(0,0,255);
  rect(curPos.x - paddleW/2, height - paddleH*2, paddleW, paddleH);
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
