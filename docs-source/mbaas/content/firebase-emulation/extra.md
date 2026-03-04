---
title: "Extra Parse Test Code"
---

# Extra Parse Test Code

To test the Parse API direct access from the same page, let's add a few lines of codes to the `index.html` file to show four new buttons to **Insert**, **Get** and **Update** a
restaurant (minimum properties) in the same collection created from the Firebase-on-Parse SDK. The application logic is
in the [`/parsef/example.js`](https://github.com/oracle/microservices-backend/blob/main/developer-preview/parsef/example.js) file.

* The modified parts included in the `index.html` file are the following:

    ```
    <!--ORACLE-->
    <div style="text-align: center">
    <p>
    <button id="insertButton">INSERT RESTAURANT</button><p>
    <button id="createButton">GET RESTAURANT</button><p>
    <button id="updateButton">SET RESTAURANT</button><p>
    <button id="queryButton" >N° RESTAURANTS</button>
    </div>
    </pre>
    <!--
    <script src="/__/firebase/9.6.6/firebase-app-compat.js"></script>
    <script src="/__/firebase/9.6.6/firebase-auth-compat.js"></script>
    <script src="/__/firebase/9.6.6/firebase-firestore-compat.js"></script> 
    <script src="/__/firebase/init.js"></script>
    -->
    <!--ORACLE-->
    <script src="//unpkg.com/navigo@6"></script>

    <!--ORACLE  -->
    <script src="/parsef/parsef.js"></script>
    <script src="https://npmcdn.com/parse/dist/parse.min.js"></script> 
    <script>
    firebase.app().options.appKey="COOLAPPV100";
    Parse.initialize(firebase.app().options.appKey);
    Parse.serverURL = "http://localhost:1337/parse";
    </script>
    <script src="/parsef/example.js"></script>
    <!-- ORACLE-->
    ```
* Reload the page to view the four new buttons. Running in the background are the Parse JS API calls for **Insert**, **Get** and **Update**, and the Firebase API to count how many restaurants are in the Parse database. For example:

    ![Filter](../../buttons.jpg "filter page")
	
* Click in sequence:

    * **Insert Restaurant**: 

        ![Insert](../../insert.jpg "insert")

    * **Get Restaurant** (Note: only Name and Category have been added):

        ![Get](../../get.jpg "get")

    * **Set Restaurant**:

        ![Set](../../set.jpg "set")

    * **Get Restaurant** (note that the additional field city has been added):

       ![Updated](../../updated.jpg "updated")

* If you click on **N° Restaurants**, you get the `size` of the restaurants based on a Firebase API call.

Next, go to the [Implemented APIs](../firebase-emulation/scope/) page to learn more.
