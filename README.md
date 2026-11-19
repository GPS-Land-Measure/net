# 🌐 GPS Land Measure (Measure Perfect) 📍
### កម្មវិធីវាស់វែងដីធ្លី និងគណនាផ្ទៃក្រឡាឆ្លាតវៃតាម GPS & AR Camera

[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platforms-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows-brightgreen?style=for-the-badge)](#supported-platforms)
[![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)](LICENSE)

An advanced, offline-first mobile and web application built with Flutter for land surveyors, real estate professionals, farmers, and civil engineers. Accurately measure land boundaries, perimeter, and area using real-time GPS tracking, high-resolution satellite imagery, RTK/NTRIP precision surveying, and futuristic AR LiDAR camera tools.

---

## 📚 Documentation (ឯកសារណែនាំ & បច្ចេកទេស)
- 📖 **[User Guide & Manual (សៀវភៅណែនាំការប្រើប្រាស់)](docs/USER_GUIDE.md)**: Detailed step-by-step instructions for field land measurement, AR camera surveying, coordinate conversions, and offline settings.
- 📐 **[System Architecture & Technical Manual (ឯកសារស្ថាបត្យកម្ម & បច្ចេកទេស)](docs/SYSTEM_DOCUMENTATION.md)**: Mathematical formulas (Haversine, Shoelace polygon area, UTM Zone 48N), system diagrams, RTK/NTRIP protocol specs, and build pipelines.

---

## 🌟 Key Features (មុខងារសំខាន់ៗ)

### 1. 🗺️ GPS Live Map Measurement (វាស់ដីតាមផែនទី GPS ជាក់ស្តែង)
- **Live Walking & Manual Pinning:** Walk around land boundaries with live GPS auto-tracking or tap points directly on high-resolution satellite imagery.
- **Instant Area & Perimeter Calculations:** Real-time computation in:
  - Square Meters ($m^2$)
  - Are (អា: $100\,m^2$)
  - Hectares (ហិកតា: $10,000\,m^2$)
- **Multiple Map Layers:** Google Satellite, Hybrid, OpenStreetMap, Topographic, and Terrain views.
- **Offline Map Caching:** Pre-cache satellite tiles for field work in remote rural areas with zero cellular reception.

### 2. 🛰️ RTK & NTRIP Precision Surveying (ប្រព័ន្ធផ្កាយរណបកម្រិតសង់ទីម៉ែត្រ)
- **NTRIP Caster Integration:** Connect external GNSS/RTK rovers via Bluetooth/USB to receive RTCM differential corrections.
- **Waypoint Coordinate Averaging:** Sample multiple GPS fixes to achieve sub-meter and centimeter-level accuracy.
- **Coordinate Conversion:** Full support for UTM (WGS84 Zone 48N/49N) and geographic latitude/longitude coordinates.

### 3. 📸 Cyberpunk AR & LiDAR Camera Measure (ម៉ាស៊ីនវាស់ដី AR & Camera)
- **Augmented Reality Measurement:** Measure land lengths, fences, and tree heights directly on screen through the camera lens.
- **Photo-Based Land Survey:** Snap a landscape photo of land plots and measure boundaries directly on the frozen image.
- **LiDAR Radar HUD:** Aerospace-grade HUD viewfinder with real-time compass azimuth badge, pitch ladder, and rangefinder concentric rings.
- **Digital Spirit Bubble Level:** Integrated 2-axis leveling gauge ($0.1^\circ$ precision) for soil grading and boundary stone alignment.

### 4. 📐 Land Plot Geometry & Calculator (គណនាប្លង់ដី & រូបរាងស្មុគស្មាញ)
- Automatic Shoelace area formula for irregular multi-point polygons.
- Built-in plot splitters, trapezoid solvers, and side-length calculation tools.
- Export measurements with timestamps, plot coordinates, and survey reports.

### 5. 📴 100% Offline Mode (ដំណើរការដោយគ្មានអ៊ីនធឺណិត)
- Designed from the ground up for remote field surveying.
- Instant offline surveyor profile without mandatory network logins.
- Local storage for all measured land plots and historical records.

---

## 📱 Screenshots (ទិដ្ឋភាពកម្មវិធី)

| AR LiDAR Measure Screen | Map GPS Surveying | Land Plot Calculator |
| :---: | :---: | :---: |
| *(Futuristic HUD & AR Target)* | *(Satellite Polygon Tracking)* | *(Area & Coordinates Report)* |

---

## 🚀 Getting Started (ការដំឡើង & ដំណើរការ)

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`>= 3.0.0 < 4.0.0`)
- [Dart SDK](https://dart.dev/get-dart)
- Android Studio / VS Code with Flutter extension
- An Android device, iOS device, or modern web browser with Location & Camera permissions enabled.

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/GPS-Land-Measure/net.git
   cd net
   ```

2. **Install Flutter dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run on your connected device or emulator:**
   ```bash
   # Run on Chrome (Web)
   flutter run -d chrome

   # Run on Android device
   flutter run -d android

   # Run on Windows Desktop
   flutter run -d windows
   ```

---

## 🛠️ Tech Stack & Architecture (បច្ចេកវិទ្យាប្រើប្រាស់)

- **Framework:** [Flutter](https://flutter.dev) (Dart)
- **Map & Geo Engine:**
  - `flutter_map` - Leaflet-based performant interactive map
  - `latlong2` - Geodesic math and geodesic distance formulas
  - `geolocator` - Real-time GNSS positioning & accuracy telemetry
  - `proj4dart` & `mgrs_dart` - UTM WGS84 coordinate projections
- **Sensors & Hardware:**
  - `sensors_plus` / Gyroscope & Accelerometer - Digital spirit level & pitch/roll estimation
  - `camera` & WebRTC - AR viewfinder & live camera feeds
  - `permission_handler` - Runtime permissions for GPS and Camera
- **Local Persistence:** `shared_preferences` for offline land records and settings.

---

## 📁 Project Structure

```text
lib/
├── main.dart                      # App entry point & offline bootstrapper
├── screens/
│   ├── home_screen.dart           # Dashboard & land calculation studio
│   ├── map_measurement_screen.dart# GPS & RTK polygon boundary survey
│   ├── camera_measure_screen.dart # AR LiDAR camera measurement & spirit level
│   └── login_screen.dart          # Authentication & offline surveyor profile
└── utils/
    ├── app_theme.dart             # Dynamic theme & color accents
    ├── camera_feed.dart           # Cross-platform camera abstraction
    ├── compass_helper.dart        # Hardware compass heading stream
    ├── geo_calculator.dart        # Haversine, Shoelace area, and UTM converters
    └── offline_helper.dart        # Network status listener & offline cache
```

---

## 👤 Author & Contributor

- **Kvav Mesa** ([@kvavmesa](https://github.com/kvavmesa))
- Email: `kvavmesa70@gmail.com`
- Organization: [GPS-Land-Measure](https://github.com/GPS-Land-Measure)

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
