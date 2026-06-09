# VeloClimApp

![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?logo=dart&logoColor=white)
![Android](https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white)
![Bluetooth](https://img.shields.io/badge/Bluetooth-0082FC?logo=bluetooth&logoColor=white)

A Flutter app used to collect data from sensors mounted on a bike.

# Description

The VeloClimApp application allows users to communicate via Bluetooth with the VeloClimap sensor, which was developed at the Lab-STICC as part of the VeloClimat project.
This initiative is sponsored by the GEOMANUM Foundation.



  VeloClimApp      | VeloClimap sensor       | 
 |-----------------|------------------|
 | <img width="300"  alt="image" src="https://github.com/user-attachments/assets/1317dd4b-8b86-45b4-8d8e-374c21a712a1" /> | <img width="300"  alt="image" src="https://github.com/user-attachments/assets/c5c09fc4-eb34-40d8-870b-92307212e8b3" />|

## Requirements

- Android 11+ (known permission issues on Android 14)
- Bluetooth and Location permissions enabled
- VeloClimap sensor device

## Build

To build :  
```bash
flutter clean
flutter pub get
flutter build apk --release
```
