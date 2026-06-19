/**
 * Apex REST endpoint that receives webhook events from Zaptilo.
 *
 * Reachable at:
 *   https://<your-org>.my.salesforce.com/services/apexrest/zaptilo/webhook
 *
 * Configure this URL in your Zaptilo workspace → Settings → Webhooks. The endpoint
 * accepts two event types:
 *
 *   1. Delivery status updates (sent / delivered / read / failed). Looks up the
 *      WhatsApp_Message__c by External_Id__c and patches Status__c.
 *
 *   2. Inbound messages from customers. Creates a new WhatsApp_Message__c with
 *      Direction = Inbound, links it to the matching Contact or Lead by phone
 *      number, and creates a Task on the related record so reps see it in
 *      Activity History.
 *
 * Auth: requires the caller to be authenticated as a Salesforce user (typically
 * a dedicated integration user). For Zaptilo to call this endpoint, generate a
 * Connected App + OAuth named credential on the Zaptilo side, OR enable Sites/
 * Public access and gate by a shared secret in the body (planned for v0.4).
 */
@RestResource(urlMapping='/zaptilo/webhook/*')
global with sharing class ZaptiloWebhookResource {

    global class WebhookEvent {
        public String type;          // 'status' or 'message'
        public String externalId;    // Zaptilo / Meta message id
        public String status;        // 'sent' | 'delivered' | 'read' | 'failed'
        public String phone;         // E.164, for inbound matching
        public String body;          // free-form text body for inbound
        public String contactName;   // optional, used when creating Lead from unknown number
    }

    global class WebhookResponse {
        public Boolean ok;
        public String message;
        public Id recordId;
    }

    @HttpPost
    global static WebhookResponse handle() {
        RestRequest req = RestContext.request;
        WebhookResponse out = new WebhookResponse();
        try {
            WebhookEvent ev = (WebhookEvent) JSON.deserialize(req.requestBody.toString(), WebhookEvent.class);
            if (ev == null || String.isBlank(ev.type)) {
                throw new IllegalArgumentException('Missing event type');
            }

            if (ev.type == 'status') {
                out.recordId = applyStatus(ev);
            } else if (ev.type == 'message') {
                out.recordId = applyInbound(ev);
            } else {
                throw new IllegalArgumentException('Unknown event type: ' + ev.type);
            }

            out.ok = true;
            return out;
        } catch (Exception e) {
            out.ok = false;
            out.message = e.getMessage();
            RestContext.response.statusCode = 400;
            return out;
        }
    }

    private static Id applyStatus(WebhookEvent ev) {
        if (String.isBlank(ev.externalId)) {
            throw new IllegalArgumentException('Status event missing externalId');
        }
        List<WhatsApp_Message__c> existing = [
            SELECT Id, Status__c
            FROM WhatsApp_Message__c
            WHERE External_Id__c = :ev.externalId
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            // Unknown external id — log nothing
            return null;
        }
        WhatsApp_Message__c m = existing[0];
        m.Status__c = String.isBlank(ev.status) ? m.Status__c : ev.status;
        update m;
        return m.Id;
    }

    private static Id applyInbound(WebhookEvent ev) {
        if (String.isBlank(ev.phone)) {
            throw new IllegalArgumentException('Inbound event missing phone');
        }
        String phone = normalizePhone(ev.phone);

        WhatsApp_Message__c msg = new WhatsApp_Message__c(
            Phone__c = phone,
            Direction__c = 'Inbound',
            Status__c = 'received',
            Body__c = ev.body,
            External_Id__c = ev.externalId
        );

        // Match against Contact first, fall back to Lead
        List<Contact> contacts = [
            SELECT Id, Name FROM Contact
            WHERE MobilePhone = :phone OR Phone = :phone
            LIMIT 1
        ];
        Task t;
        if (!contacts.isEmpty()) {
            msg.Contact__c = contacts[0].Id;
            t = new Task(
                WhoId = contacts[0].Id,
                Subject = 'WhatsApp message received',
                Description = ev.body,
                Status = 'Completed',
                Priority = 'Normal',
                ActivityDate = Date.today()
            );
        } else {
            List<Lead> leads = [
                SELECT Id, Name FROM Lead
                WHERE MobilePhone = :phone OR Phone = :phone
                LIMIT 1
            ];
            if (!leads.isEmpty()) {
                msg.Lead__c = leads[0].Id;
                t = new Task(
                    WhoId = leads[0].Id,
                    Subject = 'WhatsApp message received',
                    Description = ev.body,
                    Status = 'Completed',
                    Priority = 'Normal',
                    ActivityDate = Date.today()
                );
            }
        }

        insert msg;
        if (t != null) {
            insert t;
        }
        return msg.Id;
    }

    private static String normalizePhone(String raw) {
        if (String.isBlank(raw)) return raw;
        String stripped = raw.replaceAll('[\\s\\-\\(\\)]', '');
        if (!stripped.startsWith('+')) stripped = '+' + stripped;
        return stripped;
    }
}
