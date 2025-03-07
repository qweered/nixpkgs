{
  config,
  lib,
  stdenv,
  callPackage,
  AVFoundation,
  AudioToolbox,
  Cocoa,
  CoreFoundation,
  CoreMedia,
  CoreServices,
  CoreVideo,
  DiskArbitration,
  Foundation,
  IOKit,
  MediaToolbox,
  OpenGL,
  Security,
  SystemConfiguration,
  VideoToolbox,
  xpc,
  ipu6ep-camera-hal,
  ipu6epmtl-camera-hal,
}:

{
  inherit stdenv;

  gstreamer = callPackage ./core { inherit Cocoa CoreServices xpc; };

  gstreamermm = callPackage ./gstreamermm { };

  gst-plugins-base = callPackage ./base { inherit Cocoa OpenGL; };

  gst-plugins-good = callPackage ./good { inherit Cocoa; };

  gst-plugins-bad = callPackage ./bad {
    inherit
      AudioToolbox
      AVFoundation
      Cocoa
      CoreMedia
      CoreVideo
      Foundation
      MediaToolbox
      VideoToolbox
      ;
  };

  gst-plugins-ugly = callPackage ./ugly { inherit CoreFoundation DiskArbitration IOKit; };

  gst-plugins-rs = callPackage ./rs { inherit Security SystemConfiguration; };

  gst-rtsp-server = callPackage ./rtsp-server { };

  gst-libav = callPackage ./libav { };

  gst-devtools = callPackage ./devtools { };

  gst-editing-services = callPackage ./ges { };

  gst-vaapi = callPackage ./vaapi { };

  icamerasrc-ipu6 = callPackage ./icamerasrc { };
  icamerasrc-ipu6ep = callPackage ./icamerasrc {
    ipu6-camera-hal = ipu6ep-camera-hal;
  };
  icamerasrc-ipu6epmtl = callPackage ./icamerasrc {
    ipu6-camera-hal = ipu6epmtl-camera-hal;
  };

  # note: gst-python is in ../../python-modules/gst-python - called under python3Packages
}
// lib.optionalAttrs config.allowAliases {
  gst-plugins-viperfx = throw "'gst_all_1.gst-plugins-viperfx' was removed as it is broken and not maintained upstream"; # Added 2024-12-16
}
