# Native winegstreamer.so Rpath Notes

The native `x86_64-unix/winegstreamer.so` change is not currently a Wine source
edit. The working module was rebuilt from CrossOver 26.2 Wine source with
GStreamer enabled and with runtime library search paths that can find the
official macOS GStreamer framework.

Verified live module:

```text
/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/winegstreamer.so
sha256 8680c71a1991d51eebabe3132e127557877e7e35c6d0420ca767276c0b5250ad
```

The unsigned local build hash was:

```text
015e9fabfca6afc6f751d9f32bb4daada644eb79dda9707e37185a3df8db8185
```

The working build carried these rpaths:

```text
@loader_path/
@loader_path/../../GStreamer.framework/Libraries
/opt/local/Library/Frameworks/GStreamer.framework/Libraries
/Library/Frameworks/GStreamer.framework/Libraries
```

The bottle also sets:

```text
GST_PLUGIN_PATH=/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0
```

Without the framework plugin path and a native module that can load the
framework libraries, CrossOver's bundled GStreamer path does not expose the
`libav` decoders DQX needs (`avdec_wmv3` and `avdec_wmav2`).

Future cleanup target: replace this note with a reproducible build script under
`../build/` that emits the same module and prints the final install-name/rpath
state with `otool -l`.
