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
        if (variables != null && !variables.isEmpty()) {
            List<Map<String, String>> components = new List<Map<String, String>>();
            for (String key : variables.keySet()) {
                components.add(new Map<String, String>{
                    'type' => 'body',
                    'index' => key,
                    'value' => variables.get(key)
                });
            }
            template.put('components', components);
        }

        Map<String, Object> body = new Map<String, Object>{
            'phone' => phoneE164,
            'template' => template
        };

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

                // Some endpoints wrap the message id under data.data; others put it on data directly.
                Object innerData = dataMap.get('data');
                Map<String, Object> idHolder = innerData instanceof Map<String, Object>
                    ? (Map<String, Object>) innerData
                    : dataMap;
                if (idHolder.containsKey('id')) {
                    result.externalId = String.valueOf(idHolder.get('id'));
                }
                if (idHolder.containsKey('status')) {
                    result.status = String.valueOf(idHolder.get('status'));
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
