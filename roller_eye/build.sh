#!/usr/bin/env bash
set -euo pipefail

# Determine script directory and workspace root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$WORKSPACE_ROOT"

# Suppress mesg warnings in non-interactive shells
ttyname 0 >/dev/null 2>&1 && true || true

# Determine architecture
arch=$(uname -m)
CONTROL_SRC="$SCRIPT_DIR/DEBIAN/control.$arch"
if [[ ! -f "$CONTROL_SRC" ]]; then
    echo "Architecture not supported: $arch"
    exit 1
fi

# Determine ROS version(s)
if [[ ! -d /opt/ros ]]; then
    echo -e "\033[31mNo ROS SDK found.\033[0m"
    exit 1
fi
AVAILABLE_ROS=($(ls /opt/ros))
if (( ${#AVAILABLE_ROS[@]} == 0 )); then
    echo -e "\033[31mNo ROS SDK found.\033[0m"
    exit 1
elif (( ${#AVAILABLE_ROS[@]} > 1 )) && [[ -z "${ROS_VER:-}" ]]; then
    echo -e "\033[33mFound multiple ROS SDKs: ${AVAILABLE_ROS[*]}. Use -v option to select.\033[0m"
    exit 1
else
    ROS_VER="${ROS_VER:-${AVAILABLE_ROS[0]}}"
fi
ROS_DIR="/opt/ros/$ROS_VER"
echo -e "\033[34mScript Directory: $SCRIPT_DIR\033[0m"
echo -e "\033[34mWorkspace Root: $WORKSPACE_ROOT\033[0m"
echo -e "\033[32mROS Version: $ROS_VER\033[0m"

# Parse options: -f (clean), -r (Release), -v <version>
BUILD_TYPE=Debug
FW_APP_VER=$(git rev-parse --short HEAD)
while getopts "frv:" opt; do
  case "$opt" in
    f) rm -rf build devel ;;  # clean previous build
    r) BUILD_TYPE=Release ;;
    v) ROS_VER="$OPTARG"; ROS_DIR="/opt/ros/$ROS_VER" ;;  
    *) echo "Usage: $0 [-f] [-r] [-v ROS_VERSION]" >&2; exit 1 ;;
  esac
done
shift $((OPTIND-1))

echo -e "\033[32mBuild Type: $BUILD_TYPE\033[0m"

# Source ROS environment
source "$ROS_DIR/setup.bash"

# Build the catkin workspace
catkin_make --cmake-args -DCMAKE_BUILD_TYPE="$BUILD_TYPE" --make-args -j6

# Install targets
cd build
make install -j4
cd "$WORKSPACE_ROOT"

# Prepare Debian package directory
deb_dir="$WORKSPACE_ROOT/roller_eye_pkg"
out_deb="$WORKSPACE_ROOT/roller_eye-${arch}-${BUILD_TYPE}-${FW_APP_VER}.deb"
rm -rf "$deb_dir"
mkdir -p "$deb_dir/DEBIAN"

# Copy control file
cp "$CONTROL_SRC" "$deb_dir/DEBIAN/control"

# Copy installed rootfs files
cp -R install/rootfs/* "$deb_dir/"
rm -rf install/rootfs

# Copy ROS artifacts under proper path
install_dir="$deb_dir$ROS_DIR"
mkdir -p "$install_dir"
cp -R install/include "$install_dir/"
cp -R install/lib "$install_dir/"
cp -R install/share "$install_dir/"

# Ensure executables are executable
if [[ -f "$SCRIPT_DIR/vio/vio" ]]; then
  chmod 755 "$SCRIPT_DIR/vio/vio"
  cp "$SCRIPT_DIR/vio/vio" "$install_dir/lib/roller_eye/"
fi

# Build the final .deb
dpkg-deb -b "$deb_dir" "$out_deb"

# Cleanup
drm -rf install "$deb_dir"
echo -e "\033[32mBuild complete: $out_deb\033[0m"
