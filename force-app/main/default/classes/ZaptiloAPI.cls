/**
 * HTTP client for the Zaptilo WhatsApp Business API.
 * Reads API token and base URL from Zaptilo_Config__c (hierarchy custom setting).
 * Throws ZaptiloException on any non-2xx response or config problem.
 */
public with sharing class ZaptiloAPI {

    public class ZaptiloException extends Exception {}

    public class SendResult {
        public Boolean success;
        public String externalId;
        public String status;
        public String rawResponse;
    }

    private static final Integer TIMEOUT_MS = 30000;

    private static Zaptilo_Config__c config() {
        Zaptilo_Config__c c = Zaptilo_Config__c.getOrgDefaults();
        if (c == null || String.isBlank(c.API_Token__c)) {
            throw new ZaptiloException(
                'Zaptilo is not configured. Open the Zaptilo Settings app and paste your API token.'
            );
        }
        return c;
    }

    /**
     * Send a template message via Zaptilo's /api/send/template endpoint.
     *
     * @param phoneE164  Recipient phone number, E.164 format (e.g. +919876543210)
     * @param templateName  WhatsApp template name (must be approved)
     * @param language  Template language code (e.g. 'en' or 'en_US')
     * @param variables  Map of variable index ("1", "2", ...) to value, used to render the template
     */
    public static SendResult sendTemplate(
        String phoneE164,
        String templateName,
        String language,
        Map<String, String> variables
    ) {
        Zaptilo_Config__c c = config();

        Map<String, Object> template = new Map<String, Object>{
            'name' => templateName,
            'language' => language
        };

        // WhatsApp Cloud API expects components[].parameters[{type:'text', text:'...'}], sorted by variable index.
        if (variables != null && !variables.isEmpty()) {
            List<Integer> sortedKeys = new List<Integer>();
            for (String k : variables.keySet()) {
                try { sortedKeys.add(Integer.valueOf(k)); } catch (Exception e) {}
            }
            sortedKeys.sort();

            List<Map<String, String>> parameters = new List<Map<String, String>>();
            for (Integer key : sortedKeys) {
                String val = variables.get(String.valueOf(key));
                parameters.add(new Map<String, String>{
                    'type' => 'text',
                    'text' => val == null ? '' : val
                });
            }

            template.put('components', new List<Object>{
                new Map<String, Object>{
                    'type' => 'body',
                    'parameters' => parameters
                }
            });
        }

        Map<String, Object> body = new Map<String, Object>{
            'phone' => phoneE164,
            'template' => template
        };

        // Pass the WABA UUID if the admin pinned a Default_WABA__c — otherwise Zaptilo picks the workspace primary.
        Zaptilo_Config__c cfg = Zaptilo_Config__c.getOrgDefaults();
        if (cfg != null && String.isNotBlank(cfg.Default_WABA__c)) {
            body.put('whatsapp_connection', cfg.Default_WABA__c.trim());
        }

        return callPost('/api/send/template', body);
    }

    /**
     * Send a free-form text message via Zaptilo's /api/send endpoint.
     * Will fail if no 24-hour window is open for the recipient.
     */
    public static SendResult sendText(String phoneE164, String message) {
        Zaptilo_Config__c c = config();
        Map<String, Object> body = new Map<String, Object>{
            'phone' => phoneE164,
            'message' => message
        };
        return callPost('/api/send', body);
    }

    /**
     * Send a media message (image / document / video / audio) via /api/send/media.
     */
    public static SendResult sendMedia(
        String phoneE164,
        String mediaType,
        String mediaUrl,
        String fileName,
        String caption
    ) {
        Zaptilo_Config__c c = config();
        Map<String, Object> body = new Map<String, Object>{
            'phone' => phoneE164,
            'media_type' => mediaType,
            'media_url' => mediaUrl,
            'file_name' => fileName == null ? 'attachment' : fileName,
            'caption' => caption == null ? '' : caption
        };
        return callPost('/api/send/media', body);
    }

    /**
     * Fetch the list of WhatsApp connections (WABAs / phone numbers) in the Zaptilo workspace.
     * Used by the Settings page to populate the "Default WABA" picker so admins don't hand-paste UUIDs.
     */
    public static List<Object> listWhatsappConnections() {
        Zaptilo_Config__c c = config();
        HttpRequest req = baseRequest('/api/whatsapp-connections', 'GET', c);
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new ZaptiloException(
                'Zaptilo API returned ' + res.getStatusCode() + ': ' + res.getBody()
            );
        }
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Object data = parsed.get('data');
        if (data instanceof List<Object>) {
            return (List<Object>) data;
        }
        return new List<Object>();
    }

    /**
     * Fetch approved WhatsApp templates from the Zaptilo workspace.
     * Returns the parsed JSON list. Used by the Send modal to populate the picker.
     */
    public static List<Object> listTemplates() {
        Zaptilo_Config__c c = config();
        HttpRequest req = baseRequest('/api/templates', 'GET', c);
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new ZaptiloException(
                'Zaptilo API returned ' + res.getStatusCode() + ': ' + res.getBody()
            );
        }
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Object data = parsed.get('data');
        if (data instanceof List<Object>) {
            return (List<Object>) data;
        }
        return new List<Object>();
    }

    private static SendResult callPost(String path, Map<String, Object> body) {
        Zaptilo_Config__c c = config();
        HttpRequest req = baseRequest(path, 'POST', c);
        req.setBody(JSON.serialize(body));

        HttpResponse res = new Http().send(req);
        SendResult result = new SendResult();
        result.rawResponse = res.getBody();

        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            result.success = false;
            throw new ZaptiloException(
                'Zaptilo API returned ' + res.getStatusCode() + ': ' + res.getBody()
            );
        }

        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Object data = parsed.get('data');

            // Zaptilo's send endpoints return HTTP 200 even when Meta rejected — the actual
            // success / failure flag is on data.success. Dig in and surface failure messages.
            if (data instanceof Map<String, Object>) {
                Map<String, Object> dataMap = (Map<String, Object>) data;

                // Meta's reply shape (wrapped by Zaptilo): data.data.messages[0].id
                // Older shape: data.data.id   Bulk shape: data.id
                // Try them in order so we work with whichever endpoint variant we hit.
                Object innerData = dataMap.get('data');
                if (innerData instanceof Map<String, Object>) {
                    Map<String, Object> innerMap = (Map<String, Object>) innerData;
                    Object messages = innerMap.get('messages');
                    if (messages instanceof List<Object> && !((List<Object>) messages).isEmpty()) {
                        Object first = ((List<Object>) messages)[0];
                        if (first instanceof Map<String, Object>) {
                            Map<String, Object> firstMsg = (Map<String, Object>) first;
                            if (firstMsg.containsKey('id')) {
                                result.externalId = String.valueOf(firstMsg.get('id'));
                            }
                            if (firstMsg.containsKey('message_status')) {
                                result.status = String.valueOf(firstMsg.get('message_status'));
                            }
                        }
                    }
                    if (String.isBlank(result.externalId) && innerMap.containsKey('id')) {
                        result.externalId = String.valueOf(innerMap.get('id'));
                    }
                    if (String.isBlank(result.status) && innerMap.containsKey('status')) {
                        result.status = String.valueOf(innerMap.get('status'));
                    }
                }
                if (String.isBlank(result.externalId) && dataMap.containsKey('id')) {
                    result.externalId = String.valueOf(dataMap.get('id'));
                }
                if (String.isBlank(result.status) && dataMap.containsKey('status')) {
                    result.status = String.valueOf(dataMap.get('status'));
                }

                if (dataMap.containsKey('success') && dataMap.get('success') == false) {
                    String msg = dataMap.containsKey('message') ? String.valueOf(dataMap.get('message')) : 'Unknown error from WhatsApp';
                    throw new ZaptiloException('WhatsApp rejected the message: ' + msg);
                }
            }
            result.success = true;
        } catch (ZaptiloException e) {
            throw e;
        } catch (Exception e) {
            // Response was 2xx but unparseable — still treat as success, leave externalId blank
            result.success = true;
        }

        return result;
    }

    private static HttpRequest baseRequest(String path, String method, Zaptilo_Config__c c) {
        String base = String.isBlank(c.Base_URL__c) ? 'https://web.zaptilo.ai' : c.Base_URL__c;
        HttpRequest req = new HttpRequest();
        req.setEndpoint(base + path);
        req.setMethod(method);
        req.setHeader('Authorization', 'Bearer ' + c.API_Token__c);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(TIMEOUT_MS);
        return req;
    }
}
