---
title: "Friendly Eats Tutorial"
---

# Friendly Eats Tutorial

This is an example of porting a simple Firebase web application based on [JavaScript Firebase API - version 8](https://firebase.google.com/docs/reference/js/v8)
and describs a public [Tutorial](https://firebase.google.com/codelabs/firestore-web#0) to the [Parse Platform](https://docs.parseplatform.org/js/guide/)
leveraging an alpha quality JavaScript library included in this example.

## Complete the Original Tutorial First

We recommend that you complete the original **FriendlyEats** tutorial [instructions](https://firebase.google.com/codelabs/firestore-web#0)
using Firebase.

## Adapt the Code to Use the Firebase API Emulation

After completing the tutorial, you have a functioning application. Next, you can adapt that application to use the _Developer_ _Preview_
of the Firebase API emulation using the following steps:

1. Open the file **index.html** in an editor in the directory **/friendlyeats**.

2. Look for the Firebase library imports. For example:

    ``` 
    ...
    <script src="/__/firebase/9.6.6/firebase-app-compat.js"></script>
    <script src="/__/firebase/9.6.6/firebase-auth-compat.js"></script>
    <script src="/__/firebase/9.6.6/firebase-firestore-compat.js"></script>
    <script src="/__/firebase/init.js"></script>
    ...
    ```

    Comment out the Firebase imports and replace with the following imports and code. Change the `COOLAPPV100`
    and `serverURL` to match your Oracle Backend for Parse Platform environment. For example:
    
    ```
    <!-- comment these out: 
    <script src="/__/firebase/9.6.6/firebase-app-compat.js"></script>
    <script src="/__/firebase/9.6.6/firebase-auth-compat.js"></script>
    <script src="/__/firebase/9.6.6/firebase-firestore-compat.js"></script>
    <script src="/__/firebase/init.js"></script>
    -->
    <script src="//unpkg.com/navigo@6"></script>

    <!-- add this: -->
    <script src="/parsef/parsef.js"></script>
    <script src="https://npmcdn.com/parse/dist/parse.min.js"></script> 
    <script>
        firebase.app().options.appKey="COOLAPPV100";
        Parse.initialize(firebase.app().options.appKey);
        Parse.serverURL = "http://localhost:1337/parse";
    </script>
    ```
    
    The added lines do the following:

    * The **Firebase API emulation** library (called `parsef`) is included with this line:
	
        ```
        <script src="/parsef/parsef.js"></script>
        ```
		
        To enable the import, create a directory `parsef` under the project directory and copy the file
        [parsef.js](https://github.com/oracle/microservices-backend/blob/main/developer-preview/parsef/parsef.js) into it.

    * The **Parse JavaScript SDK** is included with this line:
	
        ```
        <script src="https://npmcdn.com/parse/dist/parse.min.js"></script> 
        ```

    * To configure communication with the Oracle Backend for Parse Platform, you must set your own `APPLICATION_ID` and `Parse serverURL`.
      This initial setup is done using these lines of code:
	  
        ```
        <script>
            firebase.app().options.appKey="COOLAPPV100";
            Parse.initialize(firebase.app().options.appKey);
            Parse.serverURL = "http://localhost:1337/parse";
        </script>
        ```
		
    Change the code according to your actual `Parse server URL` and `COOLAPPV100`.

## Repeat the Tutorial Steps With Firebase API Emulation

Repeat the original tutorial steps to load **Restaurants** and **Ratings** into the Parse Server and ensure that the original
JavaScript demo application is still running without any other changes.

1. Stop and restart the Firebase CLI.

2. Reload the web page from URL **http://127.0.0.1:5000**

    ![Mock](../../mockRestaurants.jpg "mock restaurant data")

3. Click on **ADD MOCK DATA** and wait until it finishes before adding restaurants to the Parse Server.

    ![Restaurant](../../restaurants.jpg "restaurant page")

4. Click on any restaurant. Notice that ratings are empty because the client is no longer asking for data from Firebase or Firestore.

    ![MockRatings](../../mockRatings.jpg "mock ratings page")

5. Click on **ADD MOCK RATINGS**. In a few seconds, you should see the list of ratings added. If not, close the page by clicking **X** on the upper left
  corner, and click again on the same restaurant to force a reload. For example:

    ![Ratings](../../Ratings.jpg "ratings page")

6. Click the **+** symbol on the upper right corner to add your own rating to the restaurant. For example:

    ![addRatings](../../addRatings.jpg "add ratings page")

    Notice the list is updated after saving. For example:
	
    ![listAfterAdd](../../newRatings.jpg "list after add rating")

7. Check the original sort and filter functions. Choose "Ramen" as the **Category**:

    ![Filter](../../filter.jpg "filter page")

    Notice the updated page after the filter is applied:
    
    ![Filtered](../../newList.jpg "filtered  restaurant page")
    
    **NOTE:** In this step, we do not need to add an index definition to the collection as we did in the original tutorial, since this is done
    automatically in the Parse Server.

8. You can further test the sort functionalities by adding more reviews to other restaurants. This allows you to see the number of reviews and average ratings.

Next, go to the [Extra Parse Test Code](../firebase-emulation/extra/) page to learn more.