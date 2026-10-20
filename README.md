# EnviroGuard

# Real-Time Environmental Monitoring and Alarm System
An Arduino-based environmental monitoring system with a Live Processing dashboard, sensor visualization, alarm management,and timestamped event logging.
EnviroGuard is an embedded systems project developed to monitor environmental conditions using Arduino Uno, a DHT22 temperature and humidity sensor, and a light-dependent resistor (LDR)
The system combines embedded C/C++ programming, electronics, serial communication, real-time data visualization, and CSV event logging. The Arduino monitors  the sensors and controls the physical alarms, while a Processing application displays measurements, plots measuremets history, and records changes in system status.

# Table of Contents
1. Project Objectives
2. Key Features
3. System Architecture
4. Hardware Components
5. Circuit Connections
6. Software Requirements
7. How the System Works
8. Alarm States
9. Serial Communication Protocol
10. Installation and Setup
11. Event Logging
12. Engineering Challenges and Solutions
13. Testing and Verification
14. Current Limitations
15. Future Improvements
16. Skills Demonstrated
17. Project Structure
18. Author

# Project Objectives
The main objectives of the EnviroGuard are to:
1. Monitor Temperature, relative humidity and ambient light.
2. Detect environmental conditions that cross configured alarm threshold.
3. Provide immediate local feedback through buzzer and LEDs.
4. Display live measurements and system status on a desktop dashboard.
5. Visualize recent temperature and humidity measurements.
6. Record status transition in a persistent CSV event log.
7. Practice integrating electronic hardware with embedded and desktop software.

# Key Features
Temperature monitoring using the DHT22.
Relative humidity monitoring.
Ambient light measurement using an LDR.
Real-time desktop dashboard developed with processing.
Temperature and humidity history graph.
Four system states: NORMAL, WARNING, CRITICAL, and SENSOR_FAULT.
Physical status indication using three LEDs.
Buzzer alerts for configured warning and critical conditions.
Timestamped status-transition logging to CSV.
USB serial communication at 9600.
Validation of incoming measurements and detection of stale dashboard data/
OLED display for local monitoring, with a push button for switching screens.

# System Architecture
flowchart TD
    ENV["Environment"]

    DHT["DHT22 Sensor<br/>Temperature & Humidity"]
    LDR["LDR Sensor<br/>Light Intensity"]

    ARD["Arduino Uno"]

    OLED["OLED Display"]
    ALERT["LEDs / Buzzer"]
    USB["USB Serial Communication"]

    DASH["Processing Dashboard"]

    MET["Metrics"]
    GRAPH["Graphs"]
    STATUS["Status Events"]
    CSV["alarm_events.csv"]

    ENV --> DHT
    ENV --> LDR

    DHT --> ARD
    LDR --> ARD

    ARD --> OLED
    ARD --> ALERT
    ARD --> USB

    USB --> DASH

    DASH --> MET
    DASH --> GRAPH
    DASH --> STATUS

    STATUS --> CSV

