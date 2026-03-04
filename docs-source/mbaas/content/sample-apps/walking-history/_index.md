---
Title: "Walking History"
---

# Walking History

The *Walking History* sample application uses the Parse database and GeoPoints APIs.  It is a React Native application
that allows you to walk around New York City (or simulate that in a device emulator) and it tells you about the
closest attraction or point of interest.

Here is what the *Walking History* application looks like running in the Android emulator:

![Walking History](../../mbaas-walking-history.png)

## Try the Sample

To try this sample application, you need the following: 

- An instance of Oracle Backend for Parse Platform deployed and running.
- Android Studio or Xcode, with the device emulator.
  For Android, use API level 30 and Android 11 for compatibilty with the version of React Native used in this sample.
- NodeJS to run the React Native Metro development server. 

Once you have the prerequisites, start cloning the source code for the application. For example:

```
git clone https://github.com/oracle/microservices-backend
cd microservices-backend/developer-preview/walking-history
```

This directory contains the source code for the application. In the source code, you need to update the file `App.js` to set the `APPLICATION_ID` and server URL to match your environment.
Find these lines and update those two values.  Note that the required values were provided in the output at the end of
the log for the stack apply job during the installation. For example:

```
const App: () => Node = () => {
  const isDarkMode = useColorScheme() === 'dark';

  const Parse = require('parse/react-native.js');
  Parse.setAsyncStorage(AsyncStorage);
  Parse.initialize("APPLICATION_ID");         //   <-- update this
  Parse.serverURL = 'http://1.2.3.4/parse';   //   <-- update this
```

Once you have made the updates, you can start the Metro development server by running this command:

```
npx react-native start
```

**NOTE:** The following instructions are for Android.  If you are using the iPhone operating system (iOS), process the equivalent steps in Xcode.

Open the `android` sub-directory as a project in Android Studio.  Create an emulator if you have not already done so (noting the
specific version requirements previously mentioned) and then click **Run** (or choose `Run...` from the **Run** menu) to start
the application on the emulator.

Click on the three dots symbol in the emulator menu to open the **Extended Controls**.  On the **Location** page, create a new
route from 33 Peck Slip, New York to 14 W 34th Street, New York. Set the playback speed to 4x and click on
**Play Route**. Your emulator now silumates walking around New York City for several minutes. 

As you "walk" around, you see that the application updates your location and the nearest point of interest changes.

### Explore the Parse API Usage in the Source Code

In addition to the Parse initialization in the `App.js` file, you can review the file
`components\Location.js` which uses the Parse Query API and the GeoPoints API to find a list of points of
interest that are near the current location of the device (emulator). For example:

```
// find the closest attraction and update the state
console.log("querying parse server for nearby attractions");
let query = new Parse.Query('POI');
query.near('location', new Parse.GeoPoint(currentPosition.coords.latitude,
    currentPosition.coords.longitude));
let results = await query.find().catch(err => console.log("OOPS " + JSON.stringify(err)));
```

Next, go to the [Firebase API Emulation](../firebase-emulation/) page to learn more.