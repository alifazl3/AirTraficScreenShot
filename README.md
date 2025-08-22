# Flightradar Screenshot Service

## Overview

### What Does This Project Do?
This project is a Dockerized web service that periodically captures screenshots of the Flightradar24 website (a live flight tracking map) and serves them via a simple HTTP API. It runs in a headless environment (no physical display), making it suitable for servers, cloud deployments, or containers. The service uses Selenium with Chrome to load the website, handle potential consent dialogs, and take screenshots. It ensures reliability by refreshing screenshots at configurable intervals and serving only fresh images.

Key features:
- **Automatic Refreshing**: Screenshots are taken every 60 seconds by default (configurable via environment variables).
- **On-Demand Refresh**: Users can trigger a new screenshot via an API endpoint.
- **Freshness Check**: Screenshots older than 180 seconds (configurable) are considered stale and trigger a new capture when requested.
- **Headless Operation**: Uses a virtual X server (Xorg with a dummy driver) and software rendering (SwiftShader) for stable WebGL support in containers, which is crucial for rendering Flightradar24's interactive map.
- **API Endpoints**: Provides routes to check service health, retrieve the latest screenshot, and force a refresh.
- **Error Handling**: Logs failures, retries on errors, and avoids concurrent browser sessions to prevent resource conflicts.

The primary use case is for integrating live flight tracking visuals into other applications (e.g., dashboards, bots, or monitoring tools) without needing to embed the full website or handle browser automation externally.

### How Does It Work?
The service operates as follows:

1. **Container Setup**: Built using Docker Compose. The container includes Chrome, Chromedriver, Xorg, and Python dependencies. It mounts the project directory and exposes port 5000.

2. **Startup Process** (via `entrypoint.sh`):
    - Starts a virtual X server (Xorg) with a dummy display driver to simulate a graphical environment.
    - Waits for the display to become available.
    - Prints debugging info (e.g., OpenGL renderer).
    - Launches the Python Flask app (`main.py`).

3. **Screenshot Capture** (via `main.py`):
    - Uses Selenium to launch a temporary Chrome profile (to avoid persistent state issues).
    - Navigates to the target URL (default: Flightradar24 map centered at coordinates 32.0,50.0 with zoom level 5).
    - Handles page load timeouts and consent dialogs (e.g., cookie banners) automatically.
    - Checks for WebGL2 support (using SwiftShader for software rendering, as hardware GPU isn't available in containers).
    - Saves the screenshot as a PNG file.
    - Runs in a background thread for periodic refreshes and on-demand via API.

4. **Serving Content**:
    - Flask handles HTTP requests.
    - Ensures screenshots are fresh; if not, triggers a new capture.
    - Uses locks to prevent multiple simultaneous browser instances (resource-intensive).

5. **Environment Configuration**:
    - Customizable via environment variables (e.g., URL, refresh interval, window size).
    - Defaults are set for quick setup.

The project addresses challenges like:
- Headless browsing in containers (no GPU, so software rendering is enforced).
- Website-specific issues (e.g., consent popups, WebGL requirements for maps).
- Reliability (timeouts, retries, health checks).

## File Descriptions

Below is a detailed breakdown of each file in the project, including its purpose, why it's required, and how it contributes to the overall system.

### 10-headless.conf
- **Type**: Xorg configuration file.
- **Location**: Placed in `/etc/X11/xorg.conf.d/` inside the container.
- **Purpose**: Defines a headless (virtual) display setup using a "dummy" video driver. This simulates a monitor and graphics card, allowing graphical applications (like Chrome) to run without a physical display.
- **Key Sections**:
    - `ServerFlags`: Disables automatic device detection to avoid conflicts.
    - `Monitor`: Sets up a virtual monitor with resolution 1920x1080 and refresh rates.
    - `Device`: Configures a dummy graphics device with 256MB video RAM.
    - `Screen`: Combines the device and monitor, setting 24-bit color depth.
    - `ServerLayout`: Ties everything together.
- **Why Required?**: In a headless Docker environment, there's no real display. Without this, Xorg (and thus Chrome) would fail to start. The dummy driver provides a software-emulated GPU.
- **Dependencies/Notes**: Referenced in `entrypoint.sh` when starting Xorg. Ensures compatibility with WebGL for rendering maps.

### docker-compose.yml
- **Type**: Docker Compose configuration file.
- **Purpose**: Defines how to build and run the service as a Docker container. It specifies the build context, volumes, ports, environment variables, and health checks.
- **Key Configurations**:
    - Service name: `screenshot`.
    - Builds from the current directory using a `Dockerfile` (not provided in the files, but assumed to exist; it likely installs Chrome, Chromedriver, Xorg, etc.).
    - Volumes: Mounts the project directory to `/app` for code access.
    - Ports: Exposes 5000 for the Flask app.
    - Environment: Sets display to `:99`, enables software GL, and paths for Chrome/Chromedriver.
    - Restart: Always restarts on failure.
    - SHM Size: 1GB to handle memory-intensive browser operations.
    - Healthcheck: Pings the root endpoint every 30s to ensure the service is up.
- **Why Required?**: Simplifies deployment. Without it, users would need manual Docker commands. It ensures consistent environments across machines.
- **Dependencies/Notes**: Assumes a `Dockerfile` exists (e.g., based on Ubuntu with added packages). Use `docker-compose up` to start.

### entrypoint.sh
- **Type**: Bash script (executable).
- **Purpose**: Acts as the container's entrypoint. Sets up the environment, starts the virtual display (Xorg), waits for it to initialize, and then runs the Python app.
- **Key Steps**:
    - Sets display to `:99` and creates necessary directories.
    - Cleans up old lock files to prevent startup issues.
    - Starts Xorg in the background with the dummy config, enabling extensions like GLX (for OpenGL/WebGL).
    - Waits (up to 20 attempts) for the display to be ready using `xdpyinfo`.
    - Prints GLX debug info.
    - Executes `python main.py`.
- **Why Required?**: Docker containers need an entrypoint to initialize services. This bridges the gap between container start and app launch, ensuring the graphical environment is ready.
- **Dependencies/Notes**: Relies on `10-headless.conf` for Xorg config. Handles common failures like lock files or slow startups. Logs to `/var/log/Xorg.99.log` for debugging.

### main.py
- **Type**: Python script (Flask application).
- **Purpose**: The core logic. Manages screenshot capture using Selenium, runs a background refresher thread, and exposes API endpoints via Flask.
- **Key Components**:
    - **Settings**: Environment variables for URL, refresh interval, TTL, timeout, window size.
    - **Driver Builder**: Creates a Chrome instance with options like software rendering (SwiftShader), no sandbox, and temporary user data dir.
    - **Consent Handler**: Attempts to click cookie consent buttons using various selectors and JavaScript.
    - **WebGL Check**: Verifies WebGL2 support post-load.
    - **Screenshot Function**: Loads page, waits, handles consent, saves PNG.
    - **Background Loop**: Refreshes periodically.
    - **Routes**: See "API Routes" section below.
- **Why Required?**: This is the application's brain. Without it, there's no automation or API.
- **Dependencies/Notes**: Imports Flask and Selenium. Uses locks for thread safety. Temporary profiles prevent state persistence issues.

### requirements.txt
- **Type**: Python dependencies file.
- **Content**: Lists `flask` and `selenium`.
- **Purpose**: Specifies packages needed for the app. Used by pip during build (e.g., in Dockerfile).
- **Why Required?**: Ensures reproducible installations. Flask for the web server; Selenium for browser automation.
- **Dependencies/Notes**: Minimalist. Additional libs (e.g., for Docker) are assumed in the base image.

## API Routes

The service exposes the following HTTP endpoints on port 5000:

- **GET /** (Root/Home):
    - **Description**: Health check endpoint. Returns a simple status message with the timestamp of the last successful screenshot.
    - **Response**: Plain text, e.g., "✅ Flightradar screenshot service (last_ok: 2023-10-01T12:00:00)".
    - **Usage**: For monitoring or health checks (used in docker-compose healthcheck).

- **GET /screenshot**:
    - **Description**: Serves the latest screenshot PNG. Checks if it's fresh (within TTL); if not, triggers a new capture.
    - **Response**: PNG image if available (200 OK); JSON error if not (503 Service Unavailable).
    - **Usage**: Embed in apps, e.g., `<img src="http://localhost:5000/screenshot">`.

- **GET /refresh**:
    - **Description**: Forces an immediate screenshot refresh.
    - **Response**: JSON with `ok` (true/false) and `ts` (timestamp). Status: 200 if successful, 500 if failed.
    - **Usage**: For manual updates when needed.

All routes are thread-safe and log errors.

## Setup and Usage

1. **Prerequisites**:
    - Docker and Docker Compose installed.
    - A `Dockerfile` (not provided; create one based on Ubuntu/Debian with Chrome, Chromedriver, Xorg, etc.).

2. **Build and Run**:
    - `docker-compose build`
    - `docker-compose up -d` (runs in background).

3. **Configuration**:
    - Edit environment variables in `docker-compose.yml` or via `.env` file.
    - Examples: Change `TARGET_URL` to a different map view; set `WINDOW=1920,1080` for higher res.

4. **Access**:
    - Service at `http://localhost:5000`.
    - Logs: Use `docker logs flightradar-screenshot`.

5. **Troubleshooting**:
    - Check Xorg logs: `docker exec -it flightradar-screenshot cat /var/log/Xorg.99.log`.
    - If screenshots fail: Ensure WebGL support (logs show renderer); adjust timeouts.

## Things That Need to Be Done (TODOs and Improvements)

This project is functional but can be enhanced. Potential next steps:


- **Multi-URL Support**: Allow dynamic URLs via query params (e.g., `/screenshot?url=...`).

- **Image Optimization**: Compress PNGs or support JPEG for smaller files.

- **Monitoring**: Expose Prometheus metrics for refresh success rates.

- **Testing**: Add unit tests for functions like consent handling; integration tests for Docker.

- **Performance Tweaks**: Reduce refresh interval safely; use headless Chrome directly if possible (but WebGL may still need Xorg).

- **Close sidebars in the app**: Before take the screenshot close all sidebars to expand view area

## Screenshots:

![screenshot](screenshot.png)

