//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<geolocator_apple/GeolocatorPlugin.h>)
#import <geolocator_apple/GeolocatorPlugin.h>
#else
@import geolocator_apple;
#endif

#if __has_include(<objectbox_flutter_libs/ObjectboxFlutterLibsPlugin.h>)
#import <objectbox_flutter_libs/ObjectboxFlutterLibsPlugin.h>
#else
@import objectbox_flutter_libs;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [GeolocatorPlugin registerWithRegistrar:[registry registrarForPlugin:@"GeolocatorPlugin"]];
  [ObjectboxFlutterLibsPlugin registerWithRegistrar:[registry registrarForPlugin:@"ObjectboxFlutterLibsPlugin"]];
}

@end
