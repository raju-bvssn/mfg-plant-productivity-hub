/**
 * Agentforce ↔ MuleSoft MCP bridge.
 * Each GenAiFunction flow calls this with toolName + the relevant input fields;
 * unused fields are null and the class builds the correct MCP JSON-RPC payload.
 */
public with sharing class PlantIQMCPBridge {

    public class Request {
        @InvocableVariable(label='Tool Name' required=true)
        public String toolName;

        @InvocableVariable(label='Quarter (e.g. Q1-2025)')
        public String quarter;

        @InvocableVariable(label='Plant Code (e.g. FLINT-1)')
        public String plantCode;

        @InvocableVariable(label='Idea Record ID (18-char)')
        public String ideaId;

        @InvocableVariable(label='HQ Target Record ID (18-char)')
        public String targetId;

        @InvocableVariable(label='Approver Name')
        public String approverName;
    }

    public class Result {
        @InvocableVariable(label='Result JSON')
        public String resultJson;
    }

    @InvocableMethod(label='Call PlantIQ MCP Tool' description='Calls the MuleSoft PlantIQ MCP server and returns the tool result as JSON.')
    public static List<Result> callTool(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(dispatch(req));
        }
        return results;
    }

    private static Result dispatch(Request req) {
        Result res = new Result();
        try {
            Map<String, Object> args = buildArgs(req);
            String mcpPayload = buildMcpPayload(req.toolName, args);
            String mcpApiKey = getMcpApiKey();

            HttpRequest httpReq = new HttpRequest();
            httpReq.setEndpoint('callout:PlantIQ_MuleSoft_MCP/mcp/v1');
            httpReq.setMethod('POST');
            httpReq.setHeader('Content-Type', 'application/json');
            httpReq.setHeader('x-api-key', mcpApiKey);
            httpReq.setBody(mcpPayload);
            httpReq.setTimeout(30000);

            Http http = new Http();
            HttpResponse httpRes = http.send(httpReq);

            if (httpRes.getStatusCode() == 200) {
                Map<String, Object> rpcResponse = (Map<String, Object>) JSON.deserializeUntyped(httpRes.getBody());
                Map<String, Object> rpcResult = (Map<String, Object>) rpcResponse.get('result');
                if (rpcResult != null) {
                    List<Object> content = (List<Object>) rpcResult.get('content');
                    if (content != null && !content.isEmpty()) {
                        Map<String, Object> first = (Map<String, Object>) content[0];
                        res.resultJson = (String) first.get('text');
                    } else {
                        res.resultJson = JSON.serialize(rpcResult);
                    }
                } else {
                    res.resultJson = '{"error":"' + rpcResponse.get('error') + '"}';
                }
            } else {
                res.resultJson = '{"error":"MCP HTTP ' + httpRes.getStatusCode() + '","body":"' + httpRes.getBody().abbreviate(500) + '"}';
            }
        } catch (Exception e) {
            res.resultJson = '{"error":"' + e.getMessage().replace('"', '\\"') + '"}';
        }
        return res;
    }

    private static Map<String, Object> buildArgs(Request req) {
        Map<String, Object> args = new Map<String, Object>();
        if (req.quarter != null)      args.put('quarter',       req.quarter);
        if (req.plantCode != null)    args.put('plant_code',    req.plantCode);
        if (req.ideaId != null)       args.put('idea_id',       req.ideaId);
        if (req.targetId != null)     args.put('target_id',     req.targetId);
        if (req.approverName != null) args.put('approver_name', req.approverName);
        return args;
    }

    private static String buildMcpPayload(String toolName, Map<String, Object> args) {
        Map<String, Object> payload = new Map<String, Object>{
            'jsonrpc' => '2.0',
            'id'      => String.valueOf(System.currentTimeMillis()),
            'method'  => 'tools/call',
            'params'  => new Map<String, Object>{
                'name'      => toolName,
                'arguments' => args
            }
        };
        return JSON.serialize(payload);
    }

    private static String getMcpApiKey() {
        List<PlantIQ_Config__mdt> cfg = [
            SELECT Value__c FROM PlantIQ_Config__mdt
            WHERE DeveloperName = 'MCP_Api_Key' LIMIT 1
        ];
        return cfg.isEmpty() ? '' : cfg[0].Value__c;
    }
}
