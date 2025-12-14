PImage mapImg;
Table t;

final int NUM_SITES = 33;
final int NUM_TIMES = 48;
final String[] GROUPS = {"ALL","CAR","BUS","HGV"};

int[][][] counts = new int[NUM_SITES][NUM_TIMES][GROUPS.length];
String[] timeLabels = new String[NUM_TIMES];

// Precomputed overall average totals (used when no site is selected)
float[] avgTotals = new float[NUM_TIMES];
float avgTotalsMax = 1;

float[][] sitePos = {
  {935,410},{922,477},{899,509},{874,531},{837,567},
  {742,605},{652,633},{598,645},{458,654},{356,639},
  {241,612},{175,584},{97,495},{65,473},{67,444},
  {61,414},{53,332},{163,312},{167,258},{244,197},
  {272,161},{307,152},{371,129},{431,105},{476,81},
  {508,101},{640,93},{717,111},{796,138},{838,165},
  {872,181},{886,276},{881,330}
};

int selectedSite = -1;
int currentTime = 0;
boolean playing = false;

boolean showLine = false;
final int MODE_TOTAL = 0;
final int MODE_VEHICLE = 1;
int lineMode = MODE_TOTAL;
color BAR_DEFAULT = color(170, 200, 230);   // light blue (color-blind friendly)
color BAR_SELECTED = color(60, 90, 130);    // dark blue (selected site)
color BAR_PEAK = color(220, 60, 60);        // red (highest load)

// ---- Panels ----
// Big semi-transparent overlay panel that occupies the middle area
// (leaves space for the 4 corner buttons)
int panelMarginX = 120;
int panelTop = 80;
int panelBottom = 80;
int panelCorner = 18;
// User request: make the chart panel fully opaque
int panelAlpha = 255;

// User request: allow hiding ALL charts (leave only map dots + buttons)
boolean showCharts = true;

// ---- UI (corners + top slider) ----
Button btnPlay, btnClear, btnTotal, btnVehicle;
Slider timeSlider;

void setup() {
  size(1000, 700);
  smooth();
  mapImg = loadImage("map.png");
  loadData("cordon_processed.csv");
  buildUI();
}

void draw() {
  background(255);
  image(mapImg, 0, 0, width, height);

  drawMapSites();
  if (!showCharts) {
     drawMapAlerts();
  }

  if (showCharts) {
    if (!showLine) drawBarsPanel();
    else drawLinePanel();
  }

  drawUI();

  if (playing) {
    currentTime = (currentTime + 1) % NUM_TIMES;
    delay(90);
  }
}

// ---- Data ----

void loadData(String fn) {
  t = loadTable(fn, "header");

  // init time labels fallback
  for (int i=0;i<NUM_TIMES;i++) timeLabels[i] = "t=" + i;

  for (TableRow r : t.rows()) {
    int s = r.getInt("site_id") - 1;
    int ti = r.getInt("time_index");
    String gStr = r.getString("vehicle_group");
    int gi = groupIndex(gStr);
    if (s<0||s>=NUM_SITES||ti<0||ti>=NUM_TIMES||gi<0) continue;

    counts[s][ti][gi] = r.getInt("count");

    // take labels from file (any site is fine, keep first non-empty)
    String tl = r.getString("time_label");
    if (tl != null && tl.length() > 0 && (timeLabels[ti].startsWith("t="))) {
      timeLabels[ti] = tl;
    }
  }
  computeAverageTotals();
}

int groupIndex(String g) {
  for (int i=0;i<GROUPS.length;i++) if (GROUPS[i].equals(g)) return i;
  return -1;
}

int totalAt(int s, int t) { return counts[s][t][0]; }

int maxTotalAtTime(int t) {
  int m=1;
  for (int i=0;i<NUM_SITES;i++) m=max(m, totalAt(i,t));
  return m;
}

int topSiteAtTime(int ti) {
  int best = -1;
  int bestV = -1;
  for (int s = 0; s < NUM_SITES; s++) {
    int v = totalAt(s, ti);
    if (v > bestV) {
      bestV = v;
      best = s;
    }
  }
  return best;
}
int[] top3SitesAtTime(int ti) {
  int a=-1,b=-1,c=-1;
  int va=-1,vb=-1,vc=-1;

  for (int s=0; s<NUM_SITES; s++) {
    int v = totalAt(s, ti);
    if (v > va) { c=b; vc=vb; b=a; vb=va; a=s; va=v; }
    else if (v > vb) { c=b; vc=vb; b=s; vb=v; }
    else if (v > vc) { c=s; vc=v; }
  }
  return new int[]{a,b,c};
}

// Overall average across all sites for each time index
void computeAverageTotals() {
  avgTotalsMax = 1;
  for (int ti = 0; ti < NUM_TIMES; ti++) {
    float sum = 0;
    int n = 0;
    for (int s = 0; s < NUM_SITES; s++) {
      sum += totalAt(s, ti);
      n++;
    }
    avgTotals[ti] = (n > 0) ? (sum / n) : 0;
    avgTotalsMax = max(avgTotalsMax, avgTotals[ti]);
  }
  if (avgTotalsMax <= 0) avgTotalsMax = 1;
}

float totalValueAt(int s, int ti) {
  // s < 0 means use overall average
  return (s < 0) ? avgTotals[ti] : totalAt(s, ti);
}

float vehicleValueAt(int s, int ti, int gi) {
  // gi: 1..3 (CAR/BUS/HGV); s < 0 -> average across sites
  if (s >= 0) return counts[s][ti][gi];
  float sum = 0;
  for (int ss = 0; ss < NUM_SITES; ss++) sum += counts[ss][ti][gi];
  return sum / NUM_SITES;
}

// ---- Map markers (red dots) ----
void drawMapSites() {
  // subtle red hotspots to guide selection
  noStroke();
  for (int i = 0; i < NUM_SITES; i++) {
    float x = sitePos[i][0];
    float y = sitePos[i][1];

    if (i == selectedSite) {
      fill(255, 0, 0, 210);
      ellipse(x, y, 18, 18);
      fill(255, 255, 255, 220);
      ellipse(x, y, 7, 7);
    } else {
      fill(255, 0, 0, 120);
      ellipse(x, y, 10, 10);
    }
  }
}



// ---- Overlay card (instruction / info) ----
void drawOverlayCard(int px, int py, int pw, int ph, String title, String body) {
  noStroke();
  fill(255, 220);
  rect(px, py, pw, ph, 12);

  fill(0, 200);
  textAlign(LEFT, TOP);
  textSize(14);
  text(title, px + 14, py + 12);

  fill(0, 160);
  textSize(11);
  text(body, px + 14, py + 36, pw - 28, ph - 48);
}

void drawCenterHint(String msg) {
  int cw = 540;
  int ch = 120;
  int cx = (width - cw) / 2;
  int cy = (height - ch) / 2;

  noStroke();
  fill(255, 230);        // semi-transparent white
  rect(cx, cy, cw, ch, 14);

  fill(0, 200);
  textAlign(CENTER, CENTER);
  textSize(16);          // bigger text
  text(msg, cx + cw/2, cy + ch/2);
}

// ---- Bars (overview) ----

void drawBarsPanel() {
  int x = panelMarginX;
  int y = panelTop;
  int w = width - 2*panelMarginX;
  int h = height - panelTop - panelBottom;

  noStroke();
  fill(255, panelAlpha);
  rect(x, y, w, h, panelCorner);

  fill(0, 190);
  textAlign(LEFT, TOP);
  textSize(14);
  String hl = (selectedSite<0) ? "-" : str(selectedSite+1);
  text("Bars (all sites)  |  time = " + timeLabels[currentTime] + "  |  Selected = site " + hl, x + 18, y + 16);

  // encouragement text (semi-transparent panel + clear instruction)
  fill(0, 150);
  textSize(12);
  text(
    "Tip: click a red dot on the map to pick a specific site. " +
    "Bars: red = peak, dark blue = selected.",
    x + 18, y + 38
  );

  int px = x + 86;
  int py = y + 70;
  int pw = w - 110;
  int ph = h - 110;

  // When no site is selected, replace the chart with instructions
  if (selectedSite < 0) {
    drawHowToUse(px + 10, py + 10, pw - 20, ph -20);
    return;
  }
  int topSite = topSiteAtTime(currentTime);

  drawXAxisLabel(px, y + h - 26, "X: Total count at time");
  drawYAxisLabel(x + 22, py, ph, "Y: Site (1–33)");

  stroke(0, 50);
  noFill();
  rect(px, py, pw, ph);

  int maxV = maxTotalAtTime(currentTime);
  int rowH = max(12, ph / NUM_SITES);

  for (int i=0;i<NUM_SITES;i++) {
    float v = totalAt(i, currentTime);
    float bw = map(v, 0, maxV, 2, pw - 90);
    int ry = py + i*rowH;

    stroke(0, 70);
    
    if (i == topSite) {
      fill(BAR_PEAK);
    } else if (i == selectedSite) {
      fill(BAR_SELECTED);
    } else {
      fill(BAR_DEFAULT);
    }
    
    rect(px + 30, ry + 2, bw, rowH - 4);
    if (i == topSite) {
      fill(220, 60, 60, 230);
    }

    noStroke();
    fill(0, 160);
    textAlign(LEFT, CENTER);
    textSize(11);
    text(i+1, px + 6, ry + rowH/2);

    fill(0, 130);
    text((int)v, px + 30 + bw + 8, ry + rowH/2);
  }
}

// ---- Lines (detail) ----


void drawLinePanel() {
  int x = panelMarginX;
  int y = panelTop;
  int w = width - 2*panelMarginX;
  int h = height - panelTop - panelBottom;

  noStroke();
  fill(255, panelAlpha);
  rect(x, y, w, h, panelCorner);

  // Header
  fill(0, 190);
  textAlign(LEFT, TOP);
  textSize(14);

  boolean usingAvg = (selectedSite < 0);
  String mLabel = (lineMode==MODE_TOTAL) ? "Total" : "Vehicles (CAR/BUS/HGV)";
  String who = usingAvg ? "Overall average (all sites)" : ("Site " + (selectedSite+1));
  text("Line (detail)  |  " + who + "  |  mode = " + mLabel, x + 18, y + 16);

  // Extra info text (under header)
  fill(0, 150);
  textSize(12);
  if (usingAvg) {
    text("Tip: click a red dot to view a single site. This default view shows the average trend across all sites.",
         x + 18, y + 40);
  } else {
    text("Info: dot indicates the current time step; use the slider or Play/Pause to explore changes over time.",
         x + 18, y + 40);
  }
  fill(0, 140);


  int px = x + 86;
  int py = y + 78;

  // Reserve space for legend OUTSIDE the chart area in vehicle mode
  int legendW = (lineMode==MODE_VEHICLE) ? 120 : 0;
  int pw = w - 110 - legendW;
  int ph = h - 140;

  drawXAxisLabel(px, y + h - 26, "X: Time");
  drawYAxisLabel(x + 22, py, ph, "Y: Count");

  stroke(0, 50);
  noFill();
  rect(px, py, pw, ph);

  drawTimeTicks(px, py, pw, ph);

  int s = usingAvg ? -1 : selectedSite;
  if (lineMode==MODE_TOTAL) drawLineTotal(s, px, py, pw, ph);
  else {
    drawLineVehicles(s, px, py, pw, ph);
    int lx = px + pw + 18;
    int ly = py + 10;
    drawVehicleLegend(lx, ly);
  }
}


void drawTimeTicks(int px, int py, int pw, int ph) {
  stroke(0, 35);
  fill(0, 120);
  textAlign(CENTER, TOP);
  textSize(10);

  for (int ti = 0; ti < NUM_TIMES; ti++) {
    float x = px + map(ti, 0, NUM_TIMES - 1, 0, pw);

    // minor tick every 15 min
    int tickLen = 4;

    // medium tick every 1 hour (4 steps)
    if (ti % 4 == 0) tickLen = 8;

    // major tick every 4 hours (16 steps) (optional)
    if (ti % 16 == 0) tickLen = 12;

    line(x, py + ph, x, py + ph + tickLen);

    // label every hour
    if (ti % 4 == 0) {
      text(timeLabels[ti], x, py + ph + 12);
    }
  }
}


void drawLineTotal(int s, int px, int py, int pw, int ph) {
  float maxV = 1;
  for (int t=0; t<NUM_TIMES; t++) maxV = max(maxV, totalValueAt(s, t));

  float yMax = niceCeil(maxV);
  drawYGridAndTicks(px, py, pw, ph, yMax, 5);   // <-- add this

  stroke(0);
  noFill();
  beginShape();
  for (int t=0; t<NUM_TIMES; t++) {
    float x = px + map(t, 0, NUM_TIMES-1, 0, pw);
    float y = py + ph - map(totalValueAt(s, t), 0, yMax, 0, ph); // use yMax
    vertex(x, y);
  }
  endShape();

  float cx = px + map(currentTime, 0, NUM_TIMES-1, 0, pw);
  float cy = py + ph - map(totalValueAt(s, currentTime), 0, yMax, 0, ph); // use yMax
  noStroke();
  fill(0);
  ellipse(cx, cy, 7, 7);
}



void drawLineVehicles(int s, int px, int py, int pw, int ph) {
  // 1) compute max across all 3 vehicle lines to set a shared y-scale
  float maxV = 1;
  for (int t = 0; t < NUM_TIMES; t++) {
    for (int g = 1; g < GROUPS.length; g++) {
      maxV = max(maxV, vehicleValueAt(s, t, g));
    }
  }

  // 2) make a nice y-axis upper bound and draw grid/ticks
  float yMax = niceCeil(maxV);
  drawYGridAndTicks(px, py, pw, ph, yMax, 5);

  // 3) draw CAR/BUS/HGV lines using the same yMax scale
  drawOneVehicleLine(s, 1, px, py, pw, ph, yMax); // CAR
  drawOneVehicleLine(s, 2, px, py, pw, ph, yMax); // BUS
  drawOneVehicleLine(s, 3, px, py, pw, ph, yMax); // HGV

  // 4) marker at currentTime (one dot per line)
  drawCurrentTimeMarker(s, px, py, pw, ph, yMax);

  // 5) (optional) peak markers (comment out if you don't want)
  drawPeakMarkers(s, px, py, pw, ph, yMax);
}

void drawOneVehicleLine(int s, int gi, int px, int py, int pw, int ph, float yMax) {
  // gi: 1=CAR, 2=BUS, 3=HGV

  // Color matches legend
  if (gi == 1) stroke(40, 120, 255);      // CAR
  else if (gi == 2) stroke(255, 140, 40); // BUS
  else stroke(40, 180, 90);               // HGV

  noFill();

  // 1) CAR: solid polyline
  if (gi == 1) {
    beginShape();
    for (int t = 0; t < NUM_TIMES; t++) {
      float x = px + map(t, 0, NUM_TIMES - 1, 0, pw);
      float v = vehicleValueAt(s, t, gi);
      float y = py + ph - map(v, 0, yMax, 0, ph);
      vertex(x, y);
    }
    endShape();
    return;
  }

  // BUS: solid line + small vertical ticks
  if (gi == 2) {
    beginShape();
    for (int t = 0; t < NUM_TIMES; t++) {
      float x = px + map(t, 0, NUM_TIMES - 1, 0, pw);
      float v = vehicleValueAt(s, t, gi);
      float y = py + ph - map(v, 0, yMax, 0, ph);
      vertex(x, y);
    }
    endShape();
  
    // draw small vertical ticks at each data point
    strokeWeight(1);
    for (int t = 0; t < NUM_TIMES; t++) {
      float x = px + map(t, 0, NUM_TIMES - 1, 0, pw);
      float v = vehicleValueAt(s, t, gi);
      float y = py + ph - map(v, 0, yMax, 0, ph);
      line(x, y - 4, x, y + 4);   // vertical tick
    }
    strokeWeight(1);
    return;
  }

  // 3) HGV: dashed + dots (segments + dot markers)
  // Keep dots subtle to avoid clutter
  for (int t = 0; t < NUM_TIMES - 1; t += 1) {
    float x1 = px + map(t,   0, NUM_TIMES - 1, 0, pw);
    float y1 = py + ph - map(vehicleValueAt(s, t,   gi), 0, yMax, 0, ph);

    float x2 = px + map(t+1, 0, NUM_TIMES - 1, 0, pw);
    float y2 = py + ph - map(vehicleValueAt(s, t+1, gi), 0, yMax, 0, ph);

    line(x1, y1, x2, y2);

    // dot at segment start
    noStroke();
    fill(40, 180, 90, 180);
    ellipse(x1, y1, 4, 4);
    noFill();
    stroke(40, 180, 90);
  }
}


void drawCurrentTimeMarker(int s, int px, int py, int pw, int ph, float yMax) {
  float cx = px + map(currentTime, 0, NUM_TIMES - 1, 0, pw);

  // CAR marker
  float v1 = vehicleValueAt(s, currentTime, 1);
  float y1 = py + ph - map(v1, 0, yMax, 0, ph);
  noStroke();
  fill(40, 120, 255);
  ellipse(cx, y1, 7, 7);

  // BUS marker
  float v2 = vehicleValueAt(s, currentTime, 2);
  float y2 = py + ph - map(v2, 0, yMax, 0, ph);
  fill(255, 140, 40);
  ellipse(cx, y2, 7, 7);

  // HGV marker
  float v3 = vehicleValueAt(s, currentTime, 3);
  float y3 = py + ph - map(v3, 0, yMax, 0, ph);
  fill(40, 180, 90);
  ellipse(cx, y3, 7, 7);
}
void drawPeakMarkers(int s, int px, int py, int pw, int ph, float yMax) {
  for (int gi = 1; gi <= 3; gi++) {
    int peakT = 0;
    float peakV = -1;
    for (int t = 0; t < NUM_TIMES; t++) {
      float v = vehicleValueAt(s, t, gi);
      if (v > peakV) { peakV = v; peakT = t; }
    }

    float x = px + map(peakT, 0, NUM_TIMES - 1, 0, pw);
    float y = py + ph - map(peakV, 0, yMax, 0, ph);

    // color
    if (gi == 1) fill(40, 120, 255);
    else if (gi == 2) fill(255, 140, 40);
    else fill(40, 180, 90);

    noStroke();
    ellipse(x, y, 9, 9);

    // label
    fill(0, 160);
    textAlign(LEFT, BOTTOM);
    textSize(10);
    text("peak " + nfc(peakV, 0) + " at " + timeLabels[peakT], x + 6, y - 6);
  }
}



void drawVehicleLegend(int lx, int ly) {
  textAlign(LEFT, TOP);
  textSize(11);
  fill(0, 160);
  text("Legend", lx, ly);
  ly += 16;

  // CAR — solid line
  stroke(40, 120, 255);
  line(lx, ly+6, lx+22, ly+6);
  noStroke();
  fill(0, 150);
  text("CAR (solid)", lx+28, ly);
  ly += 16;

  // BUS — solid + ticks
  stroke(255, 140, 40);
  line(lx, ly+6, lx+22, ly+6);
  for (int i = 0; i <= 22; i += 6) {
    line(lx + i, ly+3, lx + i, ly+9); // small vertical ticks
  }
  noStroke();
  fill(0, 150);
  text("BUS (ticks)", lx+28, ly);
  ly += 16;

  // HGV — dashed + dots
  stroke(40, 180, 90);
  for (int i = 0; i < 22; i += 6) {
    line(lx + i, ly+6, lx + i + 3, ly+6);
    ellipse(lx + i, ly+6, 3, 3);        // dot marker
  }
  noStroke();
  fill(0, 150);
  text("HGV (dashed + dots)", lx+28, ly);
}

// ---- Axis label helpers ----

void drawXAxisLabel(int x, int y, String s) {
  fill(0, 140);
  textAlign(LEFT, CENTER);
  textSize(11);
  text(s, x, y);
}


void drawYAxisLabel(int x, int y, int axisH, String s) {
  pushMatrix();
  translate(x, y + axisH/2.0);
  rotate(-HALF_PI);
  fill(0, 140);
  textAlign(CENTER, CENTER);
  textSize(11);
  text(s, 0, 0);
  popMatrix();
}

float niceCeil(float v) {
  if (v <= 0) return 1;
  float exp = floor(log(v) / log(10));
  float f = v / pow(10, exp); // 1..10
  float nf;
  if (f <= 1) nf = 1;
  else if (f <= 2) nf = 2;
  else if (f <= 5) nf = 5;
  else nf = 10;
  return nf * pow(10, exp);
}

void drawYGridAndTicks(int px, int py, int pw, int ph, float yMax, int ticks) {
  stroke(0, 30);
  fill(0, 120);
  textAlign(RIGHT, CENTER);
  textSize(10);

  for (int i = 0; i <= ticks; i++) {
    float t = i / (float)ticks;
    float y = py + ph - t * ph;

    line(px, y, px + pw, y);

    float val = t * yMax;
    text(nfc(val, 0), px - 8, y); // label left of chart
  }
}
int maxSiteAtTime(int ti) {
  int best = -1;
  int bestV = -1;
  for (int s = 0; s < NUM_SITES; s++) {
    int v = totalAt(s, ti);
    if (v > bestV) {
      bestV = v;
      best = s;
    }
  }
  return best;
}
void drawMapAlerts() {
  // rate limiting (optional): call updateAlertSiteIfNeeded() outside
  // Here we draw based on currentTime.

  int[] top3 = top3SitesAtTime(currentTime);
  if (top3[0] < 0) return;

  // threshold: only alert if peak is meaningfully above average
  float threshold = avgTotals[currentTime] * 1.25; // 25% above avg
  int peakSite = top3[0];
  int peakV = totalAt(peakSite, currentTime);
  if (peakV < threshold) return;

  // draw weak halos for #2 and #3 (only if they also pass threshold)
  for (int k = 1; k <= 2; k++) {
    int s = top3[k];
    if (s < 0) continue;
    int v = totalAt(s, currentTime);
    if (v < threshold) continue;
  
    float x = sitePos[s][0];
    float y = sitePos[s][1];
  
    noStroke();
    fill(60, 200, 80, 140);   // stronger green
    triangle(
      x, y + 18,
      x - 14, y - 8,
      x + 14, y - 8
    );
  }

  // draw strong warning icon for #1
  float x = sitePos[peakSite][0];
  float y = sitePos[peakSite][1];

  noStroke();
  fill(255, 200, 40, 90);
  ellipse(x, y, 40, 40);

  fill(255, 200, 40, 235);
  triangle(x, y - 18, x - 14, y + 10, x + 14, y + 10);

  fill(70);
  textAlign(CENTER, CENTER);
  textSize(12);
  text("!", x, y + 2);

  // small label next to it
  fill(0, 170);
  textAlign(LEFT, CENTER);
  textSize(11);
  text("Peak: " + peakV, x + 18, y);
}

// ---- UI ----

void buildUI() {
  btnPlay    = new Button(10, 10, 80, 36, "Play");
  btnClear   = new Button(width-90, 10, 80, 36, "Clear");
  btnTotal   = new Button(10, height-50, 100, 36, "Total");
  btnVehicle = new Button(width-110, height-50, 100, 36, "Vehicles");

  // top slider
  timeSlider = new Slider(140, 24, width-280, 10, 0, NUM_TIMES-1);
}

void drawUI() {
  btnPlay.label = playing ? "Pause" : "Play";
  btnPlay.draw();
  // When charts are hidden, "Clear" becomes a "Back" button
  btnClear.label = showCharts ? "Clear" : "Back";
  btnClear.draw();

  btnTotal.drawActive(showLine && lineMode==MODE_TOTAL);
  btnVehicle.drawActive(showLine && lineMode==MODE_VEHICLE);

  timeSlider.value = currentTime;
  timeSlider.draw();

  fill(0, 150);
  textAlign(CENTER, CENTER);
  textSize(12);
  String sTxt = (selectedSite<0) ? "site:-" : "site:"+(selectedSite+1);
  text(sTxt + " | time=" + timeLabels[currentTime], width/2, 48);
  if (!showCharts) {
    drawCenterHint("Map-only view.Press.\n Back to return to charts.\nUse Total/Vehicles for line charts. (Bars show site comparison)\nMap-only view. Press Back for charts.\nYellow = peak alert, Green = next highest.");
  }
}

// ---- Input ----

void mousePressed() {
  if (btnPlay.hit(mouseX,mouseY)) { playing=!playing; return; }
  if (btnClear.hit(mouseX,mouseY)) {
    if (showCharts) {
      // Clear ALL charts: leave only map dots + buttons
      showCharts = false;
      showLine = false;
      selectedSite = -1;
      playing = false;
    } else {
      // Back to charts
      showCharts = true;
    }
    return;
  }

  if (btnTotal.hit(mouseX,mouseY)) { lineMode=MODE_TOTAL; showCharts=true; showLine=true; return; }
  if (btnVehicle.hit(mouseX,mouseY)) { lineMode=MODE_VEHICLE; showCharts=true; showLine=true; return; }

  if (timeSlider.hit(mouseX,mouseY)) {
    currentTime = round(timeSlider.pick(mouseX));
    return;
  }

  pickSiteInvisible();
}

void pickSiteInvisible() {
  int best=-1; float d0=9999;
  for(int i=0;i<NUM_SITES;i++){
    float dx=mouseX-sitePos[i][0];
    float dy=mouseY-sitePos[i][1];
    float d=sqrt(dx*dx+dy*dy);
    if(d<18 && d<d0){d0=d;best=i;}
  }
  if(best!=-1) selectedSite=best;
}

// ---- UI helpers ----

class Button {
  int x,y,w,h; String label;
  Button(int x,int y,int w,int h,String l){
    this.x=x;this.y=y;this.w=w;this.h=h;label=l;
  }
  void draw(){ drawActive(false); }
  void drawActive(boolean a){
    stroke(0,80);
    fill(a?220:245);
    rect(x,y,w,h,6);
    fill(0);
    textAlign(CENTER,CENTER);
    textSize(12);
    text(label,x+w/2,y+h/2);
  }
  boolean hit(int mx,int my){
    return mx>=x&&mx<=x+w&&my>=y&&my<=y+h;
  }
}

class Slider {
  int x,y,w,h; float min,max,value;
  Slider(int x,int y,int w,int h,float min,float max){
    this.x=x;this.y=y;this.w=w;this.h=h;
    this.min=min;this.max=max;
  }
  void draw(){
    stroke(0,80);
    fill(255);
    rect(x,y,w,h,4);
    float k=map(value,min,max,x,x+w);
    fill(0);
    noStroke();
    ellipse(k,y+h/2,10,10);
  }
  boolean hit(int mx,int my){
    return mx>=x&&mx<=x+w&&my>=y-6&&my<=y+h+6;
  }
  float pick(int mx){
    return constrain(map(mx,x,x+w,min,max),min,max);
  }
}

// ---- How-to-use panel (two-column layout) ----
// Left column: sections 1–4
// Right column: section 5 (detailed workflow)

void drawHowToUse(int px, int py, int pw, int ph) {
  // card background
  noStroke();
  fill(255, 238);
  rect(px, py, pw, ph, 12);

  int padding = 20;
  int gutter  = 18;
  int colW    = (pw - padding*2 - gutter) / 2;

  // Keep your current comfortable offsets
  int leftX   = px + padding - 30;
  int rightX  = leftX + colW + gutter;
  int topY    = py - 25;

  // Title
  fill(0, 205);
  textAlign(LEFT, TOP);
  textSize(18);
  textLeading(22);
  text("How to use this visualisation", leftX, topY);

  int leftY  = topY + 30;
  int rightY = topY + 30;

  // -------- LEFT COLUMN --------
  leftY = drawHeadingAt("1. Overview (Map)", leftX, leftY);
  leftY = drawParaAt(
    "• Red dots: monitoring sites.\n" +
    "• Yellow ▲: highest load site at the current time (peak alert).\n" +
    "• Green ▼: next highest sites (secondary alerts, above threshold).\n" +
    "• Alerts are paced to reduce jitter and support comparison.",
    leftX, leftY, colW
  );
  leftY += 6;

  leftY = drawHeadingAt("2. Buttons", leftX, leftY);
  leftY = drawParaAt(
    "• Play/Pause: animate or freeze the time step.\n" +
    "• Total: line chart for TOTAL count.\n" +
    "• Vehicles: CAR/BUS/HGV lines (legend outside plot).\n" +
    "• Clear (charts visible): switch to Map-only, reset selection, stop animation.\n" +
    "• Back (map-only): return to charts.",
    leftX, leftY, colW
  );
  leftY += 6;

  leftY = drawHeadingAt("3. Time control", leftX, leftY);
  leftY = drawParaAt(
    "• Slider: inspect a specific time.\n" +
    "• Play: observe how congestion evolves.\n" +
    "• Pause when you spot an alert, then inspect details in charts.",
    leftX, leftY, colW
  );
  leftY += 6;

  // Split section 4 into 4A (left) and 4B (right)
  leftY = drawHeadingAt("4A. Views: Map-only & Bars", leftX, leftY);
  leftY = drawParaAt(
    "• Map-only: alerts + spatial context.\n" +
    "• Bars panel:\n" +
    "  – No site selected: help card.\n" +
    "  – Site selected: compares all sites at current time.\n" +
    "    Peak bar = red; selected site = dark.",
    leftX, leftY, colW
  );

  // -------- RIGHT COLUMN --------
  rightY = drawHeadingAt("4B. Views: Lines", rightX, rightY);
  rightY = drawParaAt(
    "• Line panel (Total):\n" +
    "  – No site selected: network average trend.\n" +
    "  – Site selected: single-site trend.\n" +
    "• Line panel (Vehicles):\n" +
    "  – CAR/BUS/HGV overlaid with legend outside plot.\n" +
    "  – Use this view to identify which group drives peaks.\n" +
    "• Tip: keep the same time step while switching views for comparison.",
    rightX, rightY, colW
  );
  rightY += 8;

  rightY = drawHeadingAt("5. Suggested workflow", rightX, rightY);
  rightY = drawParaAt(
    "A. Discover risk (Map-only)\n" +
    "• Press Clear to hide charts (Map-only).\n" +
    "• Press Play to scan time; watch alerts.\n" +
    "• Pause on a time step with a strong alert.\n\n" +
    "B. Explain the cause (Bars)\n" +
    "• Press Back to return to charts.\n" +
    "• In Bars: locate the alerted site and compare rank.\n" +
    "• Click the site to focus it (dark bar).\n\n" +
    "C. Understand patterns (Lines)\n" +
    "• Press Total: compare site trend vs network average.\n" +
    "• Press Vehicles: identify which group dominates peaks.\n" +
    "• Use the slider to compare before/after peak times.",
    rightX, rightY, colW
  );

  // Footer tip
  fill(0, 120);
  textSize(11);
  textLeading(14);

}


// ---- Column text helpers ----

int drawHeadingAt(String title, int x, int y) {
  fill(0, 185);
  textAlign(LEFT, TOP);
  textSize(14);
  textLeading(18);
  text(title, x, y);
  return y + 20;
}

String[] wrapLines(String txt, int w) {
  ArrayList<String> lines = new ArrayList<String>();
  String[] hard = split(txt, '\n');

  for (int p = 0; p < hard.length; p++) {
    String part = hard[p];

    if (part.length() == 0) { // preserve blank lines
      lines.add("");
      continue;
    }

    String[] words = splitTokens(part, " ");
    String line = "";

    for (int i = 0; i < words.length; i++) {
      String candidate = (line.length() == 0) ? words[i] : (line + " " + words[i]);
      if (textWidth(candidate) <= w) {
        line = candidate;
      } else {
        if (line.length() > 0) lines.add(line);
        line = words[i];
      }
    }
    if (line.length() > 0) lines.add(line);
  }

  return lines.toArray(new String[0]);
}

int drawParaAt(String txt, int x, int y, int w) {
  fill(0, 150);
  textAlign(LEFT, TOP);
  textSize(12);
  textLeading(16);

  String[] lines = wrapLines(txt, w);

  for (int i = 0; i < lines.length; i++) {
    text(lines[i], x, y + i * 16);
  }

  return y + lines.length * 16;
}
