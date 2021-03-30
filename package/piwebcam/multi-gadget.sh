#!/bin/sh

# Eventually we want to disable the serial interface by default
# As it can be used as a persistence exploitation vector
CONFIGURE_USB_SERIAL=false
CONFIGURE_USB_WEBCAM=true

# Now apply settings from the boot config
if [ -f "/boot/enable-serial-debug" ] ; then
  CONFIGURE_USB_SERIAL=true
fi

CONFIG=/sys/kernel/config/usb_gadget/piwebcam
mkdir -p "$CONFIG"
cd "$CONFIG" || exit 1

echo 0x1d6b > idVendor
echo 0x0104 > idProduct
echo 0x0100 > bcdDevice
echo 0x0200 > bcdUSB

echo 0xEF > bDeviceClass
echo 0x02 > bDeviceSubClass
echo 0x01 > bDeviceProtocol
echo 0x40 > bMaxPacketSize0

mkdir -p strings/0x409
mkdir -p configs/c.2
mkdir -p configs/c.2/strings/0x409
echo 100000000d2386db         > strings/0x409/serialnumber
echo "Show-me Webcam Project" > strings/0x409/manufacturer
echo "Piwebcam"               > strings/0x409/product
echo 500                      > configs/c.2/MaxPower
echo "Piwebcam"               > configs/c.2/strings/0x409/configuration

config_usb_serial () {
  mkdir -p functions/acm.usb0
  ln -s functions/acm.usb0 configs/c.2/acm.usb0
}

fps_to_interval() {
   # dwFrameInterval is in 100ns (fps = 1/(interval * 10_000_000))
   for fps in $@; do
     case "$fps" in
       5)  echo "5000000"; continue;;
       10) echo "1000000"; continue;;
       15) echo "666666"; continue;;
       25) echo "400000"; continue;;
       30) echo "333333"; continue;;
       40) echo "250000"; continue;;
       90) echo "111111"; continue;;
       *)  exit 1;
     esac
   done
}

config_frame () {
  # usage: config_frame (uncompressed u|mjpeg m) <width> <height> <default_fps> <fps>...
  FORMAT="$1"; shift
  NAME="$1"; shift
  WIDTH="$1"; shift
  HEIGHT="$1"; shift
  DEFAULT_RATE="$1"; shift

  FRAMEDIR="functions/uvc.usb0/streaming/$FORMAT/$NAME/${HEIGHT}p"

  mkdir -p "$FRAMEDIR"

  echo "$WIDTH"                    > "$FRAMEDIR"/wWidth
  echo "$HEIGHT"                   > "$FRAMEDIR"/wHeight
  fps_to_interval $DEFAULT_RATE  > "$FRAMEDIR"/dwDefaultFrameInterval
  echo $((WIDTH * HEIGHT * 80))  > "$FRAMEDIR"/dwMinBitRate
  echo $((WIDTH * HEIGHT * 160)) > "$FRAMEDIR"/dwMaxBitRate
  echo $((WIDTH * HEIGHT * 2))   > "$FRAMEDIR"/dwMaxVideoFrameBufferSize
  fps_to_interval "$@"           > "$FRAMEDIR"/dwFrameInterval
}

config_usb_webcam () {
  mkdir -p functions/uvc.usb0/control/header/h

  # 4x3
  config_frame mjpeg m  640  480 30 5 10 15 25 30 40
  config_frame mjpeg m  800  600 30 5 10 15 25 30 40
  config_frame mjpeg m 1024  768 30 5 10 15 25 30 40
  config_frame mjpeg m 1280  960 30 5 10 15 25 30
  config_frame mjpeg m 1440 1080 30 5 10 15 25 30
  config_frame mjpeg m 1600 1200 30 5 10 15 25 30
  config_frame mjpeg m 2592 1944 10 5 10 15  # experimental
  # 16x9
  config_frame mjpeg m  640  360 30 5 10 15 25 30 40
  config_frame mjpeg m  800  480 30 5 10 15 25 30 40
  config_frame mjpeg m 1280  720 30 5 10 15 25 30 40
  config_frame mjpeg m 1536  864 30 5 10 15 25 30
  config_frame mjpeg m 1600  900 30 5 10 15 25 30
  config_frame mjpeg m 1920 1080 30 5 10 15 25 30
  # uncompressed, experimental
  config_frame uncompressed u  640  480 30 5 10 15 25 30 40
  config_frame uncompressed u  800  600 30 5 10 15 25 30 40
  config_frame uncompressed u 1024  768 30 5 10 15 25 30 40
  config_frame uncompressed u 1280  960 30 5 10 15 25 30
  config_frame uncompressed u 1440 1080 30 5 10 15 25 30
  config_frame uncompressed u 1920 1080 30 5 10 15 25 30

  mkdir -p functions/uvc.usb0/streaming/header/h
  ln -s functions/uvc.usb0/streaming/mjpeg/m  functions/uvc.usb0/streaming/header/h
  ln -s functions/uvc.usb0/streaming/uncompressed/u  functions/uvc.usb0/streaming/header/h
  ln -s functions/uvc.usb0/streaming/header/h functions/uvc.usb0/streaming/class/fs
  ln -s functions/uvc.usb0/streaming/header/h functions/uvc.usb0/streaming/class/hs
  ln -s functions/uvc.usb0/control/header/h   functions/uvc.usb0/control/class/fs

  ln -s functions/uvc.usb0 configs/c.2/uvc.usb0
}

# Check if camera is installed correctly
if [ ! -e /dev/video0 ] ; then
  echo "I did not detect a camera connected to the Pi. Please check your hardware."
  CONFIGURE_USB_WEBCAM=false
  # Nobody can read the error if we don't have serial enabled!
  CONFIGURE_USB_SERIAL=true
else
  echo 1920 >/sys/module/bcm2835_v4l2/parameters/max_video_width
  echo 1080 >/sys/module/bcm2835_v4l2/parameters/max_video_height
fi

if [ "$CONFIGURE_USB_WEBCAM" = true ] ; then
  echo "Configuring USB gadget webcam interface"
  config_usb_webcam
fi

if [ "$CONFIGURE_USB_SERIAL" = true ] ; then
  echo "Configuring USB gadget serial interface"
  config_usb_serial
fi

ls /sys/class/udc > UDC

# Ensure any configfs changes are picked up
udevadm settle -t 5 || :
