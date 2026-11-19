# 📐 GPS Land Measure - Technical System Documentation
### ឯកសារបច្ចេកទេសប្រព័ន្ធ & ស្ថាបត្យកម្មកូដ (Software Architecture & Engineering Manual)

**Project Name:** GPS Land Measure (Measure Perfect)  
**Author:** Kvav Mesa ([@kvavmesa](https://github.com/kvavmesa))  
**Organization:** GPS-Land-Measure  
**Framework:** Flutter (Dart `>=3.0.0 <4.0.0`)  
**Repository:** [https://github.com/GPS-Land-Measure/net](https://github.com/GPS-Land-Measure/net)

---

## 1. System Overview (ទិដ្ឋភាពទូទៅនៃប្រព័ន្ធ)

The **GPS Land Measure** system is an offline-capable, cross-platform geospatial surveying application engineered to solve land boundary identification, irregular polygon surface calculation, and topographic estimation. The system bridges mobile sensor hardware (GNSS receivers, compass magnetometers, accelerometers, and cameras) with computational geometry algorithms to produce surveying data.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        PRESENTATION LAYER                              │
│  [ Home Dashboard ]   [ Live GPS Map ]   [ AR LiDAR Camera ]  [ Level ]│
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│                         BUSINESS LOGIC LAYER                           │
│  • GeoCalculator (Haversine, Shoelace, UTM)                            │
│  • CompassHelper (Azimuth Heading Smoother)                            │
│  • CameraFeedController (Live Viewfinder & Frame Freezing)             │
│  • OfflineHelper (Connectivity Listener & Local Fallback)              │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│                       DATA & HARDWARE LAYER                            │
│  [ Hardware GNSS/GPS ]   [ IMU Accelerometer ]   [ Camera / WebRTC ]   │
│  [ NTRIP RTCM3 Caster ]  [ Tile Layer Cache ]   [ SharedPreferences ]  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Mathematical Models & Geodesic Algorithms (រូបមន្តគណិតវិទ្យា)

### 2.1 Haversine Great-Circle Distance
Used to compute real-world distance between consecutive GPS waypoints $P_1(\phi_1, \lambda_1)$ and $P_2(\phi_2, \lambda_2)$ over the WGS84 ellipsoidal mean Earth radius ($R \approx 6,371,000\text{ m}$):

$$\Delta \phi = \phi_2 - \phi_1, \quad \Delta \lambda = \lambda_2 - \lambda_1$$

$$a = \sin^2\left(\frac{\Delta \phi}{2}\right) + \cos(\phi_1)\cos(\phi_2)\sin^2\left(\frac{\Delta \lambda}{2}\right)$$

$$c = 2 \cdot \text{atan2}\left(\sqrt{a}, \sqrt{1 - a}\right)$$

$$d = R \cdot c$$

In `lib/utils/geo_calculator.dart`:
```dart
double haversineDistance(LatLng p1, LatLng p2) {
  const double r = 6371000.0; // Earth radius in meters
  final dLat = _degToRad(p2.latitude - p1.latitude);
  final dLon = _degToRad(p2.longitude - p1.longitude);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degToRad(p1.latitude)) *
          math.cos(_degToRad(p2.latitude)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return r * c;
}
```

---

### 2.2 Gauss's Area Formula (Shoelace Algorithm for Polygons)
Used to calculate the exact closed boundary surface area of arbitrary non-self-intersecting $n$-sided polygons from vertices $(x_1, y_1), (x_2, y_2), \dots, (x_n, y_n)$:

$$\text{Area} = \frac{1}{2} \left| \sum_{i=1}^{n-1} (x_i y_{i+1} - x_{i+1} y_i) + (x_n y_1 - x_1 y_n) \right|$$

For geographic coordinates, vertices are first projected onto a local Euclidean tangent plane or UTM Cartesian projection ($x$ Easting, $y$ Northing in meters), yielding exact surface area in square meters ($m^2$).

---

### 2.3 Universal Transverse Mercator (UTM) Zone 48N Projection
Cambodia lies predominantly in **UTM Zone 48N** (Central Meridian $\lambda_0 = 105^\circ\text{ E}$). The project uses `proj4dart` to project ellipsoidal coordinates $(Lat, Lon)$ into conformal planar coordinates $(E, N)$:

$$\text{Proj4 Definition: } \texttt{+proj=utm +zone=48 +datum=WGS84 +units=m +no\_defs}$$

- **False Easting:** $500,000\text{ m}$
- **False Northing:** $0\text{ m}$ (Equator)
- **Scale Factor at Central Meridian:** $k_0 = 0.9996$

---

### 2.4 AR Perspective Pinhole Camera Calibration
In `lib/screens/camera_measure_screen.dart`, camera distance is derived from pixel screen coordinates $(u, v)$ using holding height calibration:

$$\text{Effective Scale } S = S_0 \cdot \left(\frac{H_{\text{holding}}}{1.50\text{ m}}\right)$$

where:
- $S_0 \approx 0.28\text{ cm/px}$ (calibrated baseline for modern smartphone focal lengths at ~0.8m distance).
- $H_{\text{holding}}$: adjustable user eye/chest holding height (default $1.50\text{ m}$).

The real-world distance between points $P_1(x_1, y_1)$ and $P_2(x_2, y_2)$ on screen is:

$$D = \frac{\sqrt{(x_2 - x_1)^2 + (y_2 - y_1)^2} \cdot S}{100.0} \quad (\text{meters})$$

---

### 2.5 2-Axis Tilt & Incline Equations (Digital Spirit Level)
Derives Pitch ($\theta$) and Roll ($\psi$) angles from normalized 3-axis accelerometer vector $\vec{A} = [a_x, a_y, a_z]^T$:

$$\text{Pitch } (\theta) = \arctan\left(\frac{a_y}{\sqrt{a_x^2 + a_z^2}}\right) \cdot \frac{180^\circ}{\pi}$$

$$\text{Roll } (\psi) = \arctan\left(\frac{-a_x}{a_z}\right) \cdot \frac{180^\circ}{\pi}$$

A surface is considered level when $|\theta| < 1.0^\circ$ and $|\psi| < 1.0^\circ$.

---

## 3. Screen & Component Architecture (រចនាសម្ព័ន្ធកូដ)

### 3.1 Screen Hierarchy

| File | Class | Responsibility |
| :--- | :--- | :--- |
| `lib/main.dart` | `GpsMeasureApp` | App initialization, offline bootstrap, dynamic theme provider. |
| `lib/screens/home_screen.dart` | `HomeScreen` | Central surveyor hub, manual land plot calculator, trapezoid geometry solver, history. |
| `lib/screens/map_measurement_screen.dart` | `MapMeasurementScreen` | Interactive satellite map, GPS waypoint averaging, polygon drawing, RTK/NTRIP caster listener. |
| `lib/screens/camera_measure_screen.dart` | `CameraMeasureScreen` | Futuristic AR LiDAR HUD, real-time video feed, frame snapshot measurement, 2-axis spirit level. |
| `lib/screens/login_screen.dart` | `LoginScreen` | Google OAuth login and instant 1-click offline surveyor bypass. |

---

### 3.2 Utilities & Helpers

| File | Purpose |
| :--- | :--- |
| `lib/utils/geo_calculator.dart` | Geodesic math: Haversine, Shoelace polygon area, UTM Zone 48N coordinate converters. |
| `lib/utils/compass_helper.dart` | Hardware compass listener using low-pass smoothing for azimuth degree headings. |
| `lib/utils/camera_feed.dart` | Cross-platform camera abstraction switching between Web (`HTMLVideoElement`) and native mobile. |
| `lib/utils/offline_helper.dart` | Network connectivity checker with continuous status stream. |
| `lib/utils/app_theme.dart` | Theme management with persistent primary color preferences in `SharedPreferences`. |

---

## 4. Hardware & External Device Interfaces

### 4.1 GNSS / RTK Rover Interface (NTRIP Client)
The app implements an NTRIP (Networked Transport of RTCM via Internet Protocol) client:
- **Protocol:** HTTP 1.0 over TCP (NTRIP v1.0/v2.0)
- **Data Format:** RTCM 3.x messages (1004, 1005, 1074, 1084, 1094, 1124)
- **NMEA Stream:** Continuously sends GGA sentence (`$GPGGA`) back to caster to support VRS (Virtual Reference Stations).

### 4.2 Bluetooth SPP (Serial Port Profile)
External GNSS receivers (such as Emlid Reach RS2+, Trimble R-series, Stonex S900) connect over standard Bluetooth SPP to stream raw NMEA coordinates directly to the map engine, bypassing mobile internal GPS.

---

## 5. Deployment & Build Pipeline (ការដំឡើង & បង្កើតកម្មវិធី)

### 5.1 Android Release Build
```bash
flutter build apk --release --split-per-abi
# Generates optimized APKs:
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
# build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
```

### 5.2 Web Containerized Build (Docker + Nginx)
The repository includes a ready-to-run [Dockerfile](file:///c:/Study/spds/net/Dockerfile) and [nginx.conf](file:///c:/Study/spds/net/nginx.conf):
```bash
# Build Docker image
docker build -t gps-land-measure:latest .

# Run container
docker run -d -p 8080:80 gps-land-measure:latest
```

### 5.3 Windows Desktop Build
```bash
flutter build windows --release
```

---

## 6. Security, Privacy & Data Storage

1. **Zero Cloud Telemetry Tracking:** All measured coordinates and land plot geometries remain stored locally on the user's device (`SharedPreferences`).
2. **Permission Guarding:** Location and Camera hardware permissions are requested JIT (Just-In-Time) with user-friendly explanations.
3. **No Vendor Lock-in:** Output data can be parsed directly to standard GeoJSON, KML, and CSV coordinate lists.

---

*GPS Land Measure Technical Documentation • Authored by **Kvav Mesa** ([@kvavmesa](https://github.com/kvavmesa))*

