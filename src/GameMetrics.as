/**
 * Created by Goose on 9/30/15.
 */
package {
import flash.desktop.NativeApplication;
import flash.events.Event;
import flash.net.NetworkInfo;
import flash.net.NetworkInterface;
import flash.net.SharedObject;

public class GameMetrics {

    private var appId:String;
    private var versionId:int;
    private var env:String;
    private var restHandler:RestHandler = new RestHandler();

    // The ID of the current session
    private var sessionId:String;

    // This is really just an indicator of whether or not we have successfully gotten a sessionId back
    private var initialized:Boolean = false;

    // ID of currently active level
    private var currentLevelId:String;

    // Array of current sessionActions
    // These are actions that get logged when we're not within any level
    private var sessionActions:Array;

    // Array of current level actions
    // These are actions that get logged when we are in a level
    private var levelActions:Array;

    // A unique identifier for this device within the metrics service
    private var deviceId:String;

    public function GameMetrics(appId:String, versionId:int, env:String) {
        this.appId = appId;
        this.versionId = versionId;
        this.env = env;
        setUniqueId();
        NativeApplication.nativeApplication.addEventListener(flash.events.Event.ACTIVATE, onForeground);
        NativeApplication.nativeApplication.addEventListener(flash.events.Event.DEACTIVATE, onBackground);
    }

    /**
     * Invoked when the app is resumed after being suspended
     */
    private function onForeground(event:flash.events.Event) {
        startSession();
    }

    /**
     * Invoked when app is suspended
     */
    private function onBackground(event:flash.events.Event) {
        endSession()
    }

    /**
     * Starts this session and initializes this GameMetrics
     * Also logs the start of the session
     * This MUST be called before anything else
     * @param appId the ID of the app you're collecting metrics for. This must match a registered app in the system
     * @param versionId The version of the app. This is a free form int
     * @param env the environment. This is a free form string, such as "DEV" or "PROD"
     */
    public function startSession() {
        sessionActions = new Array();
        restHandler.doRequest("/play_sessions", "POST", {'app_id' : appId, 'version_id' : versionId, 'env' : env, 'user_id' : deviceId}, function(data:Object) {
            sessionId = data.id;
            trace("Started session. Id: " + sessionId);
            initialized = true;
        },
        function() {
            trace("Unable to start session. Metrics will not be logged.");
        });
    }

    /**
     * Logs the start of a level. This will also cause any Actions logged before the next call to endLevel to be
     * saved into the level log record when endLevel is called
     */
    public function startLevel() {
        if(!sessionId) {
            trace("Cannot log level start because sessionId is not set.");
            return;
        }
        levelActions = new Array();
        restHandler.doRequest("/levels", "POST", {'app_id' : appId, 'version_id' : versionId, 'env' : env, 'session_id' : sessionId}, function(data:Object) {
                    currentLevelId = data.id;
                    trace("Started level. Id: " + currentLevelId);
                },
                function() {
                    trace("Unable to start level.");
                });
    }

    /**
     * Logs the given data blob, either associating it with the current level in progress, or the session
     * @param data the blob to log
     */
    public function logAction(data:Object) {
        if(!sessionId) return;
        if(currentLevelId) {
            levelActions.push(data);
        } else {
            sessionActions.push(data);
        }
    }

    /**
     * Logs the end of the level, as well as any actions logged since the start of the previous level.
     * @param data any additional data to log (i.e. how many players, final score, etc.)
     */
    public function endLevel(data:Object = null) {
        if(!sessionId) {
            trace("No sessionId exists. Will not log anything")
            return;
        }
        if(!currentLevelId) {
            trace("No current level exists. Call startLevel before endLevel");
            return;
        }
        var postData:Object = {'actions' : levelActions};
        if(data) {
            postData['data'] = data;
        }
        restHandler.doRequest("/levels/" + currentLevelId, "PATCH", postData, function(data:Object) {
                    trace("Ended level " + currentLevelId);
                    currentLevelId = null;
                },
                function() {
                    trace("Unable to end level.");
                });
    }

    /**
     * Logs the end of the session and closes it out
     * @param data any additional data to log
     */
    public function endSession(data:Object = null) {
        if(!sessionId) {
            trace("No session is currently active. Will not end session.")
            return;
        }
        var postData:Object = {'actions' : levelActions, 'closed_on' : new Date()};
        if(data) {
            postData['data'] = data;
        }
        restHandler.doRequest("/play_sessions/" + sessionId, "PATCH", postData, function(data:Object) {
                    trace("Ended session " + sessionId);
                    sessionId = null;
                    initialized = false;
                },
                function() {
                    trace("Unable to end session.");
                });
    }

    // Attempts to set the deviceId to a unique ID
    // First it will attempt to get the MAC address. If that fails, it will
    // generate a persisted unique ID
    // If persistence fails, a unique ID will be generated each time the app is started
    private function setUniqueId() {
        if(NetworkInfo.isSupported) {
            for each(var nwi:NetworkInterface in NetworkInfo.networkInfo) {
                if (nwi.hardwareAddress) {
                    deviceId = nwi.hardwareAddress;
                    break;
                }
            }
        }
        if(!deviceId) {
            var sharedObj:SharedObject = SharedObject.getLocal("kmetricsObj");
            if(sharedObj) {
                if(!sharedObj.data["id"]) {
                    sharedObj.data["id"] = generateRandomId();
                }
                deviceId = sharedObj.data["id"];
            } else {
                // If we get here, we're kinda screwed as far as having a persistent unique ID goes. Just generate a new one each time
                deviceId = "DEADBEEF" + generateRandomId();
            }
        }
    }


    /**
     * Generates a unique hexidecimal string
     */
    private function generateRandomId():String{
        var chars:String = "ABCDEF0123456789";
        var num_chars:Number = chars.length - 1;
        var randomChar:String = "";

        for (var i:Number = 0; i < 32; i++){
            randomChar += chars.charAt(Math.floor(Math.random() * num_chars));
        }
        return randomChar;
    }
}
}
