@RestResource(urlMapping='/slack-callback/*')
global with sharing class SlackCallbackController {

    @HttpPost
    global static void doPost() {
        RestRequest req  = RestContext.request;
        RestResponse res = RestContext.response;

        String body = req.requestBody.toString();

        // Slack sends interactions as URL-encoded payload= parameter
        String jsonPayload = body;
        if (body.startsWith('payload=')) {
            jsonPayload = EncodingUtil.urlDecode(body.substringAfter('payload='), 'UTF-8');
        }

        Map<String, Object> payload;
        try {
            payload = (Map<String, Object>) JSON.deserializeUntyped(jsonPayload);
        } catch (Exception e) {
            res.statusCode = 400;
            return;
        }

        List<Object> actions = (List<Object>) payload.get('actions');
        if (actions == null || actions.isEmpty()) {
            res.statusCode = 200;
            return;
        }

        Map<String, Object> action = (Map<String, Object>) actions[0];
        String actionId  = (String) action.get('action_id');
        String ideaIdStr = (String) action.get('value');

        Map<String, Object> userMap = (Map<String, Object>) payload.get('user');
        String slackUsername = userMap != null ? (String) userMap.get('name') : 'Slack User';

        if (String.isBlank(ideaIdStr) || String.isBlank(actionId)) {
            res.statusCode = 200;
            return;
        }

        Id ideaId = (Id) ideaIdStr;
        String newStatus;
        String replyText;

        if (actionId == 'approve_idea') {
            newStatus  = 'Approved';
            replyText  = '✅ Approved by ' + slackUsername;
        } else if (actionId == 'reject_idea') {
            newStatus  = 'Rejected';
            replyText  = '❌ Rejected by ' + slackUsername;
        } else if (actionId == 'more_info_idea') {
            postMoreInfo(ideaId, payload);
            res.statusCode = 200;
            return;
        } else {
            res.statusCode = 200;
            return;
        }

        try {
            GWB_Productivity_Idea__c idea = [
                SELECT Id, Status__c, Slack_Message_TS__c,
                       Assumptions__c, Benchmark_Evidence__c, Required_Validations__c
                FROM GWB_Productivity_Idea__c WHERE Id = :ideaId LIMIT 1
            ];
            idea.Status__c = newStatus;
            update idea;
            postThreadReply(payload, replyText);
        } catch (Exception e) {
            res.statusCode = 500;
            return;
        }

        res.statusCode = 200;
    }

    private static void postMoreInfo(Id ideaId, Map<String, Object> payload) {
        List<GWB_Productivity_Idea__c> ideas = [
            SELECT Id, Name, Assumptions__c, Benchmark_Evidence__c,
                   Required_Validations__c, Risk_Notes__c, FTE_Impact__c, Dollar_Impact__c
            FROM GWB_Productivity_Idea__c WHERE Id = :ideaId LIMIT 1
        ];
        if (ideas.isEmpty()) return;

        GWB_Productivity_Idea__c idea = ideas[0];
        String sfUrl = URL.getOrgDomainUrl().toExternalForm() + '/' + ideaId;

        String msg = '*More Details: ' + idea.Name + '*\n\n' +
            '*Assumptions:* ' + (String.isNotBlank(idea.Assumptions__c) ? idea.Assumptions__c : 'None recorded') + '\n\n' +
            '*Benchmark Evidence:* ' + (String.isNotBlank(idea.Benchmark_Evidence__c) ? idea.Benchmark_Evidence__c : 'None') + '\n\n' +
            '*Required Validations:* ' + (String.isNotBlank(idea.Required_Validations__c) ? idea.Required_Validations__c : 'None') + '\n\n' +
            '*Risk Notes:* ' + (String.isNotBlank(idea.Risk_Notes__c) ? idea.Risk_Notes__c : 'None') + '\n\n' +
            '<' + sfUrl + '|View in Salesforce>';

        postThreadReply(payload, msg);
    }

    private static void postThreadReply(Map<String, Object> payload, String text) {
        try {
            String webhookUrl = getWebhookUrl();
            if (String.isBlank(webhookUrl)) return;

            Map<String, Object> container = (Map<String, Object>) payload.get('container');
            String channelId = container != null ? (String) container.get('channel_id') : null;
            String messageTs = container != null ? (String) container.get('message_ts') : null;

            if (String.isBlank(channelId) || String.isBlank(messageTs)) return;

            // Use chat.postMessage for thread replies — webhook doesn't support thread_ts
            // For the hackathon demo, posting to the channel is sufficient via webhook
            Map<String, Object> replyPayload = new Map<String, Object>{
                'text' => text
            };

            HttpRequest httpReq = new HttpRequest();
            httpReq.setEndpoint(webhookUrl);
            httpReq.setMethod('POST');
            httpReq.setHeader('Content-Type', 'application/json');
            httpReq.setBody(JSON.serialize(replyPayload));
            httpReq.setTimeout(8000);
            new Http().send(httpReq);
        } catch (Exception e) {
            // Best-effort; don't fail the callback
        }
    }

    private static String getWebhookUrl() {
        List<PlantIQ_Config__mdt> configs = [
            SELECT Value__c FROM PlantIQ_Config__mdt
            WHERE DeveloperName = 'Slack_Webhook_URL'
            LIMIT 1
        ];
        return configs.isEmpty() ? null : configs[0].Value__c;
    }
}
