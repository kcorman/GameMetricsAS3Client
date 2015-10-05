/**
 * Created by Goose on 9/30/15.
 */
package {
import flash.display.Sprite;
import flash.events.*;
import flash.net.*;
import flash.net.SharedObject;

public class RestHandler {

    private static const HOST_KEY:String = "host";
    private static const DEFAULT_SERVER:String = "http://williamthefoe.ddns.net:29777"
    public var basePath:String;

    // Checks to see if the base path needs updating
    // This allows us to change the location of the metrics server without deploying a new app version. The old server
    // still needs to stay up, but it won't receive much traffic
    private function getBasePath() {
        // first, check the shared object
        var shared:SharedObject = SharedObject.getLocal("metricsServerInfo");
        if(!shared.data[HOST_KEY]) {
            shared.data[HOST_KEY] = DEFAULT_SERVER;
        }
        basePath = shared.data[HOST_KEY];
        // now check to see if the target server has a better suggestion
        doRequest("/server_info/leader", "GET", null, function(data:Object) {
            basePath = data["leader"];
            shared.data[HOST_KEY] = basePath;
            trace("Set base path to server leader of: " + basePath);
            shared.flush();
        }, function() {
            trace("Failed to get leader for server: " + basePath + ", reverting to default: " + DEFAULT_SERVER);
            basePath = DEFAULT_SERVER;
        });
    }

    public function RestHandler() {
        getBasePath();
    }

    /**
     * Performs an HTTP request for the given resource, using the given method, and using the provided
     * data if it is present.
     * @param resource the resource to access
     * @param method the method to use (i.e. GET, POST, PATCH, PUT, DELETE)
     * @param data data to provide (only used for POST & PATCH)
     * @param success Callback function for success. The function is of the form function(data:Object) where the data
     * is the JSON payload returned from the server, or null if no content was returned
     * @param failure callback function for a failure. The function is of the form function() with no parameters.
     */
    public function doRequest(resource:String, method:String, data:Object=null, success:Function=null, failure:Function=null) {
        var urlLoader:URLLoader = new URLLoader();
        if (success != null) {
            urlLoader.addEventListener(Event.COMPLETE, function (event:Event) {
                var loader:URLLoader = URLLoader(event.target);
                trace("completeHandler: " + loader.data);
                var parsedData:Object = null;
                if(loader.data) {
                    parsedData = JSON.parse(loader.data);
                }
                success(parsedData);
            });
        }
        if (failure != null) {
            urlLoader.addEventListener(HTTPStatusEvent.HTTP_STATUS, function(event:Event) {
                var loader:URLLoader = URLLoader(event.target);
                var statusEvent:HTTPStatusEvent = HTTPStatusEvent(event);
                // Only dispatch failure if status is not 2xx
                if((int(statusEvent.status / 100)) != 2) {
                    trace("status handler: " + event);
                    failure.call();
                }
            });
        }

        urlLoader.addEventListener(IOErrorEvent.IO_ERROR, function(event:Event) {
            trace("IO Error: " + IOErrorEvent(event));
        })
        var request:URLRequest = new URLRequest(basePath + resource);
        var headers:Array = [
            new URLRequestHeader("Content-Type", "application/json"),
            new URLRequestHeader("Accept", "application/json")
        ];
        request.requestHeaders = headers;
        if(data) {
            request.data = JSON.stringify(data);
            trace("Sending data: " + request.data);
        }
        request.method = method;
        try {
            trace("Trying to load");
            urlLoader.load(request);
        } catch (error:Error) {
            trace("Unable to load requested document.");
        }
    }
}
}
