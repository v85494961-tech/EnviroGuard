#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <DHT.h>
#include <math.h>

const byte DHT_PIN = 2;
const byte BUTTON_PIN = 3;
const byte LDR_PIN = A0;

const byte GREEN_LED = 9;
const byte YELLOW_LED = 10;
const byte RED_LED = 11;
const byte BUZZER_PIN = 8;

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
#define OLED_ADDRESS 0x3C
#define DHT_TYPE DHT22

Adafruit_SSD1306 display(
  SCREEN_WIDTH,
  SCREEN_HEIGHT,
  &Wire,
  OLED_RESET
);

DHT dht(DHT_PIN, DHT_TYPE);

bool oledOK = false;

const float WARNING_TEMP = 30.0;
const float CRITICAL_TEMP = 35.0;

const float LOW_HUMIDITY = 25.0;
const float HIGH_HUMIDITY = 75.0;

const int DARK_LIGHT_THRESHOLD = 250;
const int BRIGHT_LIGHT_THRESHOLD = 800;

const bool ENABLE_LIGHT_ALARM = false;
const bool ENABLE_HUMIDITY_ALARM = true;

const unsigned long SENSOR_INTERVAL = 2500;
const unsigned long DISPLAY_INTERVAL = 200;
const unsigned long BUTTON_DEBOUNCE = 40;
const unsigned long RED_FLASH_INTERVAL = 250;

const unsigned long WARNING_BEEP_ON = 100;
const unsigned long WARNING_BEEP_OFF = 700;

const unsigned long CRITICAL_BEEP_ON = 150;
const unsigned long CRITICAL_BEEP_OFF = 200;

const unsigned int WARNING_FREQUENCY = 1000;
const unsigned int CRITICAL_FREQUENCY = 2000;

float temperature = NAN;
float humidity = NAN;

int lightRaw = 0;
bool sensorOK = false;

enum AlarmState {
  NORMAL,
  WARNING,
  CRITICAL,
  SENSOR_FAULT
};

AlarmState alarmState = SENSOR_FAULT;
AlarmState previousLedState = SENSOR_FAULT;
AlarmState previousBuzzerState = SENSOR_FAULT;

unsigned long lastSensorRead = 0;
unsigned long lastDisplayUpdate = 0;

byte screenNumber = 0;

bool lastButtonReading = HIGH;
bool stableButtonState = HIGH;

unsigned long lastDebounceTime = 0;
unsigned long lastRedFlash = 0;
bool redLedOn = false;

unsigned long lastBuzzerChange = 0;
bool buzzerOn = false;

void allLedsOff() {
  digitalWrite(GREEN_LED, LOW);
  digitalWrite(YELLOW_LED, LOW);
  digitalWrite(RED_LED, LOW);
}

void updateStatusLEDs() {
  unsigned long now = millis();

  if (alarmState != previousLedState) {
    redLedOn = false;
    lastRedFlash = now;
    previousLedState = alarmState;
  }

  switch (alarmState) {
    case NORMAL:
      digitalWrite(GREEN_LED, HIGH);
      digitalWrite(YELLOW_LED, LOW);
      digitalWrite(RED_LED, LOW);
      break;

    case WARNING:
      digitalWrite(GREEN_LED, LOW);
      digitalWrite(YELLOW_LED, HIGH);
      digitalWrite(RED_LED, LOW);
      break;

    case CRITICAL:
      digitalWrite(GREEN_LED, LOW);
      digitalWrite(YELLOW_LED, LOW);

      if (now - lastRedFlash >= RED_FLASH_INTERVAL) {
        lastRedFlash = now;
        redLedOn = !redLedOn;
      }

      digitalWrite(RED_LED, redLedOn ? HIGH : LOW);
      break;

    case SENSOR_FAULT:
      digitalWrite(GREEN_LED, LOW);
      digitalWrite(YELLOW_LED, LOW);
      digitalWrite(RED_LED, HIGH);
      break;
  }
}

void readSensors() {
  float newTemperature = dht.readTemperature();
  float newHumidity = dht.readHumidity();

  lightRaw = analogRead(LDR_PIN);

  bool invalidReading =
    isnan(newTemperature) ||
    isnan(newHumidity) ||
    newTemperature < -40.0 ||
    newTemperature > 80.0 ||
    newHumidity < 0.0 ||
    newHumidity > 100.0;

  if (invalidReading) {
    sensorOK = false;
    temperature = NAN;
    humidity = NAN;
    alarmState = SENSOR_FAULT;
    return;
  }

  temperature = newTemperature;
  humidity = newHumidity;
  sensorOK = true;
}

void determineAlarmState() {
  if (!sensorOK) {
    alarmState = SENSOR_FAULT;
    return;
  }

  if (temperature >= CRITICAL_TEMP) {
    alarmState = CRITICAL;
    return;
  }

  bool temperatureWarning =
    temperature >= WARNING_TEMP;

  bool humidityWarning =
    ENABLE_HUMIDITY_ALARM &&
    (
      humidity < LOW_HUMIDITY ||
      humidity > HIGH_HUMIDITY
    );

  bool lightWarning =
    ENABLE_LIGHT_ALARM &&
    (
      lightRaw < DARK_LIGHT_THRESHOLD ||
      lightRaw > BRIGHT_LIGHT_THRESHOLD
    );

  if (
    temperatureWarning ||
    humidityWarning ||
    lightWarning
  ) {
    alarmState = WARNING;
  } else {
    alarmState = NORMAL;
  }
}

void updateBuzzer() {
  unsigned long now = millis();

  if (alarmState != previousBuzzerState) {
    noTone(BUZZER_PIN);
    buzzerOn = false;
    lastBuzzerChange = now;

    previousBuzzerState = alarmState;

    if (alarmState == WARNING) {
      tone(BUZZER_PIN, WARNING_FREQUENCY);
      buzzerOn = true;
    } else if (alarmState == CRITICAL) {
      tone(BUZZER_PIN, CRITICAL_FREQUENCY);
      buzzerOn = true;
    }

    return;
  }

  if (
    alarmState == NORMAL ||
    alarmState == SENSOR_FAULT
  ) {
    noTone(BUZZER_PIN);
    buzzerOn = false;
    return;
  }

  unsigned long onDuration;
  unsigned long offDuration;
  unsigned int frequency;

  if (alarmState == WARNING) {
    onDuration = WARNING_BEEP_ON;
    offDuration = WARNING_BEEP_OFF;
    frequency = WARNING_FREQUENCY;
  } else {
    onDuration = CRITICAL_BEEP_ON;
    offDuration = CRITICAL_BEEP_OFF;
    frequency = CRITICAL_FREQUENCY;
  }

  unsigned long requiredDuration =
    buzzerOn ? onDuration : offDuration;

  if (now - lastBuzzerChange >= requiredDuration) {
    lastBuzzerChange = now;
    buzzerOn = !buzzerOn;

    if (buzzerOn) {
      tone(BUZZER_PIN, frequency);
    } else {
      noTone(BUZZER_PIN);
    }
  }
}

void updateButton() {
  bool reading = digitalRead(BUTTON_PIN);

  if (reading != lastButtonReading) {
    lastDebounceTime = millis();
  }

  if (millis() - lastDebounceTime >= BUTTON_DEBOUNCE) {
    if (reading != stableButtonState) {
      stableButtonState = reading;

      if (stableButtonState == LOW) {
        screenNumber = (screenNumber + 1) % 3;
      }
    }
  }

  lastButtonReading = reading;
}

void drawHeader() {
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);

  display.println(F("ENVIROGUARD"));

  display.drawLine(
    0, 10, 127, 10,
    SSD1306_WHITE
  );
}

void drawEnvironmentScreen() {
  drawHeader();

  display.setCursor(0, 15);

  if (sensorOK) {
    display.print(F("Temp: "));
    display.print(temperature, 1);
    display.println(F(" C"));

    display.print(F("Humidity: "));
    display.print(humidity, 1);
    display.println(F(" %"));
  } else {
    display.println(F("DHT22 SENSOR ERROR"));
    display.println(F("Check sensor wiring"));
  }

  display.setCursor(0, 42);
  display.print(F("Status: "));

  switch (alarmState) {
    case NORMAL:
      display.println(F("NORMAL"));
      break;

    case WARNING:
      display.println(F("WARNING"));
      break;

    case CRITICAL:
      display.println(F("CRITICAL"));
      break;

    case SENSOR_FAULT:
      display.println(F("SENSOR FAULT"));
      break;
  }

  display.setCursor(0, 56);
  display.println(F("Button: next screen"));
}

void drawLightScreen() {
  drawHeader();

  display.setCursor(0, 14);
  display.println(F("AMBIENT LIGHT"));

  display.print(F("LDR ADC: "));
  display.println(lightRaw);

  display.setCursor(0, 30);

  if (lightRaw < DARK_LIGHT_THRESHOLD) {
    display.println(F("Condition: DARK"));
  } else if (lightRaw > BRIGHT_LIGHT_THRESHOLD) {
    display.println(F("Condition: BRIGHT"));
  } else {
    display.println(F("Condition: MODERATE"));
  }

  display.setCursor(0, 44);
  display.print(F("Light alarm: "));
  display.println(
    ENABLE_LIGHT_ALARM ? F("ON") : F("OFF")
  );

  display.setCursor(0, 56);
  display.println(F("LDR monitoring"));
}

void drawThresholdScreen() {
  drawHeader();

  display.setCursor(0, 13);
  display.println(F("ALARM THRESHOLDS"));

  display.print(F("Warning: "));
  display.print(WARNING_TEMP, 1);
  display.println(F(" C"));

  display.print(F("Critical: "));
  display.print(CRITICAL_TEMP, 1);
  display.println(F(" C"));

  display.print(F("Humidity: "));
  display.print(LOW_HUMIDITY, 0);
  display.print(F("-"));
  display.print(HIGH_HUMIDITY, 0);
  display.println(F("%"));

  display.setCursor(0, 56);
  display.println(F("Edit thresholds in code"));
}

void updateDisplay() {
  if (!oledOK) {
    return;
  }

  display.clearDisplay();

  switch (screenNumber) {
    case 0:
      drawEnvironmentScreen();
      break;

    case 1:
      drawLightScreen();
      break;

    case 2:
      drawThresholdScreen();
      break;
  }

  display.display();
}

const char* getStateName() {
  switch (alarmState) {
    case NORMAL:
      return "NORMAL";

    case WARNING:
      return "WARNING";

    case CRITICAL:
      return "CRITICAL";

    case SENSOR_FAULT:
      return "SENSOR_FAULT";

    default:
      return "UNKNOWN";
  }
}

void sendSerialData() {
  Serial.print(millis());
  Serial.print(',');

  if (sensorOK) {
    Serial.print(temperature, 1);
    Serial.print(',');
    Serial.print(humidity, 1);
  } else {
    Serial.print(F("nan,nan"));
  }

  Serial.print(',');
  Serial.print(lightRaw);
  Serial.print(',');
  Serial.print(getStateName());
  Serial.print(',');
  Serial.println(sensorOK ? 1 : 0);
}

void setup() {
  Serial.begin(9600);

  pinMode(BUTTON_PIN, INPUT_PULLUP);

  pinMode(GREEN_LED, OUTPUT);
  pinMode(YELLOW_LED, OUTPUT);
  pinMode(RED_LED, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT);

  allLedsOff();
  noTone(BUZZER_PIN);

  dht.begin();

  oledOK = display.begin(
    SSD1306_SWITCHCAPVCC,
    OLED_ADDRESS
  );

  if (oledOK) {
    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    display.setTextSize(2);

    display.setCursor(8, 12);
    display.println(F("ENVIRO"));

    display.setCursor(8, 35);
    display.println(F("GUARD"));

    display.display();

    delay(1500);
  } else {
    Serial.println(F("DIAGNOSTIC: OLED initialization failed"));
  }

  readSensors();
  determineAlarmState();

  previousBuzzerState = SENSOR_FAULT;
  previousLedState = SENSOR_FAULT;

  lastRedFlash = millis();
  lastBuzzerChange = millis();

  updateStatusLEDs();
  updateBuzzer();

  Serial.println(
    F("time_ms,temperature_c,humidity_percent,"
      "ldr_adc,status,sensor_ok")
  );

  updateDisplay();

  lastSensorRead = millis();
  lastDisplayUpdate = millis();
}

void loop() {
  unsigned long now = millis();

  updateButton();

  if (now - lastSensorRead >= SENSOR_INTERVAL) {
    lastSensorRead = now;

    readSensors();
    determineAlarmState();
    sendSerialData();
  }

  updateStatusLEDs();
  updateBuzzer();

  if (now - lastDisplayUpdate >= DISPLAY_INTERVAL) {
    lastDisplayUpdate = now;
    updateDisplay();
  }
}