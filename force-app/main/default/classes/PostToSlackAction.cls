public with sharing class PostToSlackAction {

    public class SlackRequest {
        @InvocableVariable(label='Idea Record ID' required=true)
        public Id ideaId;
        @InvocableVariable(label='Plant Name')
        public String plantName;
        @InvocableVariable(label='Shop Name')
        public String shopName;
        @InvocableVariable(label='Gap To Target FTE')
        public Decimal gapToTarget;
        @InvocableVariable(label='Quarter')
        public String quarter;
        @InvocableVariable(label='Idea Title')
        public String ideaTitle;
        @InvocableVariable(label='FTE Impact')
        public Decimal fteImpact;
        @InvocableVariable(label='Dollar Impact')
        public Decimal dollarImpact;
        @InvocableVariable(label='Confidence Score')
        public Integer confidenceScore;
        @InvocableVariable(label='Effort')
        public String effort;
        @InvocableVariable(label='Benchmark Evidence')
        public String benchmarkEvidence;
    }

    public class SlackResponse {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Slack Message TS')
        public String messageTs;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(label='Post to Slack' description='Posts a Block Kit recommendation card to Slack with Approve/Reject/More Info buttons')
    public static List<SlackResponse> postToSlack(List<SlackRequest> requests) {
        List<SlackResponse> responses = new List<SlackResponse>();
        for (SlackRequest req : requests) {
            responses.add(doPost(req));
        }
        return responses;
    }

    private static SlackResponse doPost(SlackRequest req) {
        SlackResponse resp = new SlackResponse();
        try {
            String webhookUrl = getWebhookUrl();
            if (String.isBlank(webhookUrl)) {
                resp.success = false;
                resp.errorMessage = 'Slack webhook URL not configured. Set Custom Metadata or Named Credential.';
                return resp;
            }

            String sfBaseUrl = URL.getOrgDomainUrl().toExternalForm();
            String recordUrl = sfBaseUrl + '/' + req.ideaId;
            String dollarStr = req.dollarImpact != null ? '$' + req.dollarImpact.format() : 'TBD';
            String fteStr    = req.fteImpact != null ? req.fteImpact.format() + ' FTE' : 'TBD';
            String gapStr    = req.gapToTarget != null ? req.gapToTarget.format() + ' FTE gap' : 'unknown gap';
            String confStr   = req.confidenceScore != null ? String.valueOf(req.confidenceScore) + '%' : 'N/A';

            Map<String, Object> payload = new Map<String, Object>{
                'text' => 'PlantIQ AI Recommendation for ' + req.plantName,
                'blocks' => new List<Object>{
                    new Map<String, Object>{
                        'type' => 'header',
                        'text' => new Map<String, Object>{ 'type' => 'plain_text', 'text' => 'PlantIQ AI Recommendation' }
                    },
                    new Map<String, Object>{
                        'type' => 'section',
                        'fields' => new List<Object>{
                            new Map<String, Object>{ 'type' => 'mrkdwn', 'text' => '*Plant:*\n' + req.plantName },
                            new Map<String, Object>{ 'type' => 'mrkdwn', 'text' => '*Shop:*\n' + req.shopName },
                            new Map<String, Object>{ 'type' => 'mrkdwn', 'text' => '*HQ Gap:*\n' + gapStr },
                            new Map<String, Object>{ 'type' => 'mrkdwn', 'text' => '*Quarter:*\n' + req.quarter }
                        }
                    },
                    new Map<String, Object>{
                        'type' => 'section',
                        'text' => new Map<String, Object>{
                            'type' => 'mrkdwn',
                            'text' => '*Recommended Initiative:* ' + req.ideaTitle + '\n' +
                                      '*FTE Impact:* ' + fteStr + '  |  *Value:* ' + dollarStr +
                                      '  |  *Effort:* ' + (req.effort != null ? req.effort : 'TBD') +
                                      '  |  *Confidence:* ' + confStr
                        }
                    },
                    new Map<String, Object>{
                        'type' => 'section',
                        'text' => new Map<String, Object>{
                            'type' => 'mrkdwn',
                            'text' => '_Evidence: ' + (String.isNotBlank(req.benchmarkEvidence) ? req.benchmarkEvidence : 'No benchmark data') + '_'
                        }
                    },
                    new Map<String, Object>{
                        'type' => 'actions',
                        'elements' => new List<Object>{
                            new Map<String, Object>{
                                'type' => 'button',
                                'style' => 'primary',
                                'text' => new Map<String, Object>{ 'type' => 'plain_text', 'text' => 'Approve' },
                                'action_id' => 'approve_idea',
                                'value' => req.ideaId
                            },
                            new Map<String, Object>{
                                'type' => 'button',
                                'style' => 'danger',
                                'text' => new Map<String, Object>{ 'type' => 'plain_text', 'text' => 'Reject' },
                                'action_id' => 'reject_idea',
                                'value' => req.ideaId
                            },
                            new Map<String, Object>{
                                'type' => 'button',
                                'text' => new Map<String, Object>{ 'type' => 'plain_text', 'text' => 'More Info' },
                                'action_id' => 'more_info_idea',
                                'value' => req.ideaId,
                                'url' => recordUrl
                            }
                        }
                    }
                }
            };

            HttpRequest httpReq = new HttpRequest();
            httpReq.setEndpoint(webhookUrl);
            httpReq.setMethod('POST');
            httpReq.setHeader('Content-Type', 'application/json');
            httpReq.setBody(JSON.serialize(payload));
            httpReq.setTimeout(10000);

            Http http = new Http();
            HttpResponse httpResp = http.send(httpReq);

            if (httpResp.getStatusCode() == 200) {
                resp.success   = true;
                resp.messageTs = String.valueOf(System.now().getTime());
                GWB_Productivity_Idea__c upd = new GWB_Productivity_Idea__c(
                    Id = req.ideaId,
                    Slack_Message_TS__c = resp.messageTs
                );
                update upd;
            } else {
                resp.success      = false;
                resp.errorMessage = 'Slack HTTP ' + httpResp.getStatusCode() + ': ' + httpResp.getBody();
            }
        } catch (Exception e) {
            resp.success      = false;
            resp.errorMessage = e.getMessage();
        }
        return resp;
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
