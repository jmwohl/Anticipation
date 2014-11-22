import gab.opencv.*;
import processing.video.*;

PImage src, dst;
OpenCV opencv;

Capture cam;

int camW = 640;
int camH = 480;

// calculate trajectory based on current frame and how many frames back?
int frameHistory = 5;

// how many frames into the future to project?
int projection = 10;

PVector samples[];

int frameCounter = 0;

PVector curPos = new PVector();
PVector curVel = new PVector();
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
  
  samples = new PVector[frameHistory];
  
  cam = new Capture(this, camW, camH);
  cam.start();
  
  opencv = new OpenCV(this, cam);
}

void draw() {

  if (cam.available()) { 
    // Reads the new frame
    cam.read();
  }
  
  opencv.loadImage(cam);
  
  opencv.gray();
  float thresh = map(mouseY, 0, height, 0, 100); 
  opencv.threshold(int(thresh));
  opencv.invert();
  
  dst = opencv.getOutput();
  
  contours = opencv.findContours();
   //<>//
  image(dst, 0, 0);

  // focus on only the biggest contour
  if (contours.size() > 0) {
    Contour contour = contours.get(0);
    
    ArrayList<PVector> points = contour.getPolygonApproximation().getPoints();
    PVector centroid = calculateCentroid(points);
    
    // draw the centroid, justforthehellavit.
    fill(255, 0, 0);
    ellipse(centroid.x, centroid.y, 10, 10);
    
    // add current pos to pos list
    int frame = frameCount % frameHistory;
    println(frame);
    samples[frame] = curPos = centroid;
  }
  
  if (samples[0] != null) {
    println("prev.x: " + samples[0].x);
    println("cur.x: " + samples[frameHistory - 1].x);
  }
  
  // calculate velocity vector
  if (samples[0] != null) {
    PVector prevPos = samples[0];
    curVel.x = curPos.x - prevPos.x;
    curVel.y = curPos.y - prevPos.y;
    drawVelocity();
  }
}

void keyPressed() {
  if (key == 'f' || key == 'F') {
    frame.setSize(displayWidth, displayHeight);
  }
}

// draw the velocity vector
void drawVelocity() {
  stroke(0, 255, 0);
  line(curPos.x, curPos.y, curPos.x + curVel.x, curPos.y + curVel.y);
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
