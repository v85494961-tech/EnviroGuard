
import processing.serial.Serial;
import java.io.File;
import java.io.FileWriter;
import java.io.BufferedWriter;
import java.io.PrintWriter;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

processing.serial.Serial arduino = null;
PrintWriter eventFile = null;

final String SERIAL_PORT = "COM4";
final int BAUD_RATE = 9600;
final int MAX_HISTORY = 120;
final int MAX_EVENTS = 8;
final int DATA_TIMEOUT_MS = 7000;

boolean connected = false;
boolean sensorOK = false;
boolean shuttingDown = false;

int lastDataTime = 0;
int historyCount = 0;
int eventCount = 0;
int lightRaw = 0;

String status = "WAITING";
String lastLoggedStatus = "";

float temperature = Float.NaN;
float humidity = Float.NaN;
float smoothTemp = Float.NaN;
float smoothHum = Float.NaN;

float[] tempHistory = new float[MAX_HISTORY];
float[] humHistory = new float[MAX_HISTORY];

String[] eventLines = new String[MAX_EVENTS];

DateTimeFormatter clockFormat =
  DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

color bg = color(10, 16, 24);
color panel = color(19, 28, 39);
color muted = color(145, 160, 177);
color green = color(54, 220, 151);
color cyan = color(56, 190, 235);
color amber = color(255, 181, 71);
color red = color(255, 76, 88);
color white = color(238, 244, 250);

void setup() {
  size(1200, 800);
  surface.setTitle("EnviroGuard | Environmental Monitoring");
  surface.setResizable(true);
  smooth(4);

  initializeEventLog();
  initializeSerial();
}

void initializeEventLog() {
  try {
    File logFile = new File(sketchPath("alarm_events.csv"));

    boolean needsHeader =
      !logFile.exists() || logFile.length() == 0;

    eventFile = new PrintWriter(
      new BufferedWriter(
        new FileWriter(logFile, true)
      )
    );

    if (needsHeader) {
      eventFile.println(
        "timestamp,status,temperature_c," +
        "humidity_percent,ldr_adc,sensor_ok"
      );
      eventFile.flush();
    }

    println("Event log: " + logFile.getAbsolutePath());

  } catch (Exception e) {
    eventFile = null;
    println("ERROR: Could not open event log.");
    e.printStackTrace();
  }
}

void initializeSerial() {
  println("Available serial ports:");
  printArray(processing.serial.Serial.list());

  try {
    arduino = new processing.serial.Serial(
      this,
      SERIAL_PORT,
      BAUD_RATE
    );

    arduino.clear();
    arduino.bufferUntil('\n');

    println("Listening on " + SERIAL_PORT);

  } catch (Exception e) {
    arduino = null;
    println("Could not open " + SERIAL_PORT);
    println("Check the port and close Arduino Serial Monitor.");
    e.printStackTrace();
  }
}

void serialEvent(processing.serial.Serial port) {
  String line = port.readStringUntil('\n');

  if (line == null) return;

  line = trim(line);

  if (line.length() == 0 ||
      line.startsWith("time_ms") ||
      line.startsWith("DIAGNOSTIC:")) {
    return;
  }

  String[] v = split(line, ',');

  if (v.length != 6) {
    println("Ignored invalid CSV row: " + line);
    return;
  }

  try {
    Long.parseLong(trim(v[0]));

    int newLight = Integer.parseInt(trim(v[3]));
    String newStatus = trim(v[4]);
    int sensorFlag = Integer.parseInt(trim(v[5]));

    if (newLight < 0 || newLight > 1023) return;
    if (sensorFlag != 0 && sensorFlag != 1) return;

    boolean recognizedStatus =
      newStatus.equals("NORMAL") ||
      newStatus.equals("WARNING") ||
      newStatus.equals("CRITICAL") ||
      newStatus.equals("SENSOR_FAULT");

    if (!recognizedStatus) return;

    float newTemp = Float.NaN;
    float newHum = Float.NaN;

    boolean validMeasurement = sensorFlag == 1;

    if (validMeasurement) {
      newTemp = Float.parseFloat(trim(v[1]));
      newHum = Float.parseFloat(trim(v[2]));

      validMeasurement =
        !Float.isNaN(newTemp) &&
        !Float.isInfinite(newTemp) &&
        !Float.isNaN(newHum) &&
        !Float.isInfinite(newHum) &&
        newTemp >= -40 && newTemp <= 80 &&
        newHum >= 0 && newHum <= 100;
    }

    if (newStatus.equals("SENSOR_FAULT")) {
      validMeasurement = false;
    }

    connected = true;
    lastDataTime = millis();
    lightRaw = newLight;

    if (!validMeasurement) {
      sensorOK = false;
      status = "SENSOR_FAULT";
      temperature = Float.NaN;
      humidity = Float.NaN;
    } else {
      sensorOK = true;
      temperature = newTemp;
      humidity = newHum;
      status = newStatus;

      if (Float.isNaN(smoothTemp)) {
        smoothTemp = temperature;
        smoothHum = humidity;
      }

      addHistory(temperature, humidity);
    }

    if (!status.equals(lastLoggedStatus)) {
      logStatusChange();
      lastLoggedStatus = status;
    }

  } catch (Exception e) {
    println("Could not parse serial row: " + line);
  }
}

void addHistory(float t, float h) {
  if (historyCount < MAX_HISTORY) {
    tempHistory[historyCount] = t;
    humHistory[historyCount] = h;
    historyCount++;
  } else {
    arrayCopy(tempHistory, 1, tempHistory, 0, MAX_HISTORY - 1);
    arrayCopy(humHistory, 1, humHistory, 0, MAX_HISTORY - 1);

    tempHistory[MAX_HISTORY - 1] = t;
    humHistory[MAX_HISTORY - 1] = h;
  }
}

void logStatusChange() {
  String timestamp =
    LocalDateTime.now().format(clockFormat);

  String t = sensorOK ? nf(temperature, 0, 2) : "";
  String h = sensorOK ? nf(humidity, 0, 2) : "";
  String flag = sensorOK ? "1" : "0";

  String csvRow =
    timestamp + "," + status + "," + t + "," +
    h + "," + lightRaw + "," + flag;

  if (eventFile != null) {
    eventFile.println(csvRow);
    eventFile.flush();
  } else {
    println("WARNING: Event log unavailable.");
  }

  String displayLine =
    timestamp.substring(11) + "  " + status;

  if (eventCount < MAX_EVENTS) {
    eventLines[eventCount] = displayLine;
    eventCount++;
  } else {
    arrayCopy(eventLines, 1, eventLines, 0, MAX_EVENTS - 1);
    eventLines[MAX_EVENTS - 1] = displayLine;
  }

  println("EVENT: " + csvRow);
}

void draw() {
  background(bg);

  float s = max(
    0.5,
    min(width / 1200.0, height / 800.0)
  );

  float margin = 28 * s;
  float gap = 14 * s;

  boolean fresh =
    connected &&
    millis() - lastDataTime < DATA_TIMEOUT_MS;

  boolean valid = fresh && sensorOK;

  if (valid) {
    if (Float.isNaN(smoothTemp)) {
      smoothTemp = temperature;
      smoothHum = humidity;
    } else {
      smoothTemp = lerp(smoothTemp, temperature, 0.15);
      smoothHum = lerp(smoothHum, humidity, 0.15);
    }
  }

  drawHeader(s, fresh, valid);

  float top = 88 * s;
  float cardW = (width - 2 * margin - 2 * gap) / 3.0;
  float cardH = 108 * s;

  drawMetricCard(
    margin, top, cardW, cardH,
    "TEMPERATURE",
    valid ? nf(smoothTemp, 0, 1) : "--",
    "DEG C", amber, s
  );

  drawMetricCard(
    margin + cardW + gap, top, cardW, cardH,
    "HUMIDITY",
    valid ? nf(smoothHum, 0, 1) : "--",
    "% RH", cyan, s
  );

  drawMetricCard(
    margin + 2 * (cardW + gap), top, cardW, cardH,
    "AMBIENT LIGHT",
    fresh ? str(lightRaw) : "--",
    "ADC / 1023", green, s
  );

  float midY = top + cardH + 14 * s;
  float midH = 133 * s;

  float leftW = (width - 2 * margin - gap) * 0.43;
  float rightX = margin + leftW + gap;
  float rightW = width - rightX - margin;

  drawStatusPanel(
    margin, midY, leftW, midH, fresh, valid, s
  );

  drawEventPanel(
    rightX, midY, rightW, midH, s
  );

  float graphY = midY + midH + 14 * s;
  float graphH = max(65 * s, height - graphY - 34 * s);
  float graphW = (width - 2 * margin - gap) / 2.0;

  drawGraph(
    margin, graphY, graphW, graphH,
    "TEMPERATURE HISTORY (C)",
    tempHistory, historyCount, -10, 50, amber, s
  );

  drawGraph(
    margin + graphW + gap, graphY, graphW, graphH,
    "HUMIDITY HISTORY (%)",
    humHistory, historyCount, 0, 100, cyan, s
  );

  fill(muted);
  textSize(10 * s);
  textAlign(LEFT, CENTER);

  text(
    "ENVIROGUARD | " + SERIAL_PORT + " | " +
    BAUD_RATE + " BAUD",
    margin, height - 14 * s
  );

  textAlign(RIGHT, CENTER);

  String footer =
    !fresh ? "WAITING FOR DATA" :
    !valid ? "SENSOR FAULT" : "LIVE MONITORING";

  fill(!fresh ? red : !valid ? amber : green);
  text(footer, width - margin, height - 14 * s);
}

void drawHeader(float s, boolean fresh, boolean valid) {
  fill(white);
  textAlign(LEFT, CENTER);
  textSize(25 * s);
  text("ENVIROGUARD", 28 * s, 24 * s);

  fill(muted);
  textSize(11 * s);
  text(
    "REAL-TIME ENVIRONMENTAL MONITORING",
    30 * s, 49 * s
  );

  color indicator = !fresh ? red : !valid ? amber : green;

  noStroke();
  fill(indicator);
  ellipse(width - 150 * s, 27 * s, 9 * s, 9 * s);

  fill(white);
  textAlign(RIGHT, CENTER);
  textSize(12 * s);

  String label =
    !fresh ? "OFFLINE" :
    !valid ? "SENSOR FAULT" : "ONLINE";

  text(label, width - 28 * s, 27 * s);

  stroke(49, 68, 83);
  line(28 * s, 67 * s, width - 28 * s, 67 * s);
}

void drawMetricCard(
  float x, float y, float w, float h,
  String label, String value, String unit,
  color accent, float s
) {
  noStroke();
  fill(panel);
  rect(x, y, w, h, 12 * s);

  fill(accent);
  rect(x, y, 4 * s, h, 2 * s);

  fill(muted);
  textAlign(LEFT, CENTER);
  textSize(11 * s);
  text(label, x + 15 * s, y + 20 * s);

  fill(white);
  textSize(29 * s);
  text(value, x + 15 * s, y + 55 * s);

  fill(accent);
  textSize(10 * s);
  text(unit, x + 16 * s, y + h - 14 * s);
}

void drawStatusPanel(
  float x, float y, float w, float h,
  boolean fresh, boolean valid, float s
) {
  noStroke();
  fill(panel);
  rect(x, y, w, h, 12 * s);

  fill(white);
  textAlign(LEFT, CENTER);
  textSize(13 * s);
  text("CURRENT SYSTEM STATUS", x + 15 * s, y + 20 * s);

  color stateColor;
  String stateText;

  if (!fresh) {
    stateColor = red;
    stateText = "NO LIVE DATA";
  } else if (!valid) {
    stateColor = amber;
    stateText = "SENSOR FAULT";
  } else if (status.equals("CRITICAL")) {
    stateColor = red;
    stateText = "CRITICAL";
  } else if (status.equals("WARNING")) {
    stateColor = amber;
    stateText = "WARNING";
  } else {
    stateColor = green;
    stateText = "NORMAL";
  }

  fill(stateColor);
  textSize(23 * s);
  text(stateText, x + 15 * s, y + 53 * s);

  fill(muted);
  textSize(10 * s);
  text(
    "Alarm decisions are made by the Arduino.",
    x + 15 * s, y + h - 15 * s
  );
}

void drawEventPanel(
  float x, float y, float w, float h, float s
) {
  noStroke();
  fill(panel);
  rect(x, y, w, h, 12 * s);

  fill(white);
  textAlign(LEFT, CENTER);
  textSize(12 * s);
  text("RECENT STATUS EVENTS", x + 13 * s, y + 16 * s);

  textSize(10 * s);

  float lineHeight = 12 * s;

  int visible = min(
    eventCount,
    max(1, floor((h - 39 * s) / lineHeight))
  );

  int start = max(0, eventCount - visible);

  for (int i = start; i < eventCount; i++) {
    String entry = eventLines[i];

    if (entry.indexOf("CRITICAL") >= 0 ||
        entry.indexOf("SENSOR_FAULT") >= 0) {
      fill(red);
    } else if (entry.indexOf("WARNING") >= 0) {
      fill(amber);
    } else {
      fill(green);
    }

    text(
      entry,
      x + 13 * s,
      y + 34 * s + (i - start) * lineHeight
    );
  }

  if (eventCount == 0) {
    fill(muted);
    text(
      "Waiting for first status update...",
      x + 13 * s, y + 46 * s
    );
  }
}

void drawGraph(
  float x, float y, float w, float h,
  String graphTitle, float[] values, int count,
  float minV, float maxV, color graphColor, float s
) {
  noStroke();
  fill(panel);
  rect(x, y, w, h, 12 * s);

  fill(graphColor);
  textAlign(LEFT, CENTER);
  textSize(11 * s);
  text(graphTitle, x + 14 * s, y + 16 * s);

  float gx = x + 35 * s;
  float gy = y + 31 * s;
  float gw = w - 47 * s;
  float gh = h - 48 * s;

  if (gw <= 0 || gh <= 0) return;

  stroke(42, 58, 71);
  strokeWeight(1);

  fill(muted);
  textAlign(RIGHT, CENTER);
  textSize(9 * s);

  for (int i = 0; i <= 4; i++) {
    float fraction = i / 4.0;
    float yy = gy + gh * fraction;
    float axisValue = maxV - (maxV - minV) * fraction;

    line(gx, yy, gx + gw, yy);
    text(nf(axisValue, 0, 0), gx - 5 * s, yy);
  }

  if (count < 2) {
    fill(muted);
    textAlign(CENTER, CENTER);
    textSize(10 * s);
    text(
      "Collecting measurements...",
      gx + gw / 2, gy + gh / 2
    );
    return;
  }

  noFill();
  stroke(graphColor);
  strokeWeight(max(1, 2 * s));

  beginShape();

  for (int i = 0; i < count; i++) {
    float xx = map(
      i, 0, max(1, count - 1), gx, gx + gw
    );

    float yy = map(
      constrain(values[i], minV, maxV),
      minV, maxV, gy + gh, gy
    );

    vertex(xx, yy);
  }

  endShape();
}

void keyPressed() {
  if (key == 'c' || key == 'C') {
    historyCount = 0;
    println("Graph history cleared.");
  }

  if (key == 's' || key == 'S') {
    println("Available serial ports:");
    printArray(processing.serial.Serial.list());
  }
}

void exit() {
  if (shuttingDown) return;
  shuttingDown = true;

  if (arduino != null) {
    try {
      arduino.stop();
    } catch (Exception e) {
      println("Error closing serial connection.");
    }
    arduino = null;
  }

  if (eventFile != null) {
    try {
      eventFile.flush();
      eventFile.close();
    } catch (Exception e) {
      println("Error closing event log.");
    }
    eventFile = null;
  }

  super.exit();
}
