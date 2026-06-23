public with sharing class LaunchRecommendationAction {

    public class Request {
        @InvocableVariable(required=true label='HQ Target Record ID')
        public Id targetId;
    }

    @InvocableMethod(label='Launch PlantIQ Recommendation' category='PlantIQ')
    public static void launch(List<Request> requests) {
        for (Request req : requests) {
            System.enqueueJob(new PlantIQQueueable(req.targetId));
        }
    }
}
