/**
 * Invocable Apex method that exposes Zaptilo's send-template action to Flow Builder,
 * Process Builder, Apex Triggers, and Schedule-Triggered Flows.
 *
 * Drag "Send WhatsApp Template" into any Flow, point it at a Contact or Lead record,
 * pick a template name, and supply up to 3 variable values.
 */
public with sharing class ZaptiloFlowAction {

    public class Request {
        @InvocableVariable(
            label='Record Id'
            description='The Contact or Lead record to send the WhatsApp message to. Pulls phone from Mobile then Phone.'
            required=true
        )
        public Id recordId;

        @InvocableVariable(
            label='Template Name'
            description='The exact API name of the approved WhatsApp template.'
            required=true
        )
        public String templateName;

        @InvocableVariable(
            label='Language'
            description='Template language code (e.g. en, en_US, hi). Defaults to en.'
        )
        public String language;

        @InvocableVariable(label='Variable 1' description='Maps to placeholder {{1}}.')
        public String variable1;

        @InvocableVariable(label='Variable 2' description='Maps to placeholder {{2}}.')
        public String variable2;

        @InvocableVariable(label='Variable 3' description='Maps to placeholder {{3}}.')
        public String variable3;

        @InvocableVariable(label='Variable 4' description='Maps to placeholder {{4}}.')
        public String variable4;

        @InvocableVariable(label='Variable 5' description='Maps to placeholder {{5}}.')
        public String variable5;
    }

    public class Result {
        @InvocableVariable(label='Success' description='True if the send was accepted by Zaptilo.')
        public Boolean success;

        @InvocableVariable(label='Message Log Id' description='Id of the WhatsApp_Message__c log record. Blank if not logged.')
        public Id messageLogId;

        @InvocableVariable(label='External Message Id' description='Zaptilo / Meta message id.')
        public String externalId;

        @InvocableVariable(label='Error' description='Human-readable error string if success is false.')
        public String errorMessage;
    }

    /**
     * Flow / Process Builder entry point. One Request → one Result.
     * Skips records that have Do_Not_WhatsApp__c = true (returns success=false with explanation).
     */
    @InvocableMethod(
        label='Send WhatsApp Template (Zaptilo)'
        description='Sends an approved WhatsApp template via Zaptilo. Checks Do_Not_WhatsApp__c first.'
        category='Zaptilo WhatsApp'
    )
    public static List<Result> sendTemplate(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request r : requests) {
            results.add(processOne(r));
        }
        return results;
    }

    private static Result processOne(Request r) {
        Result out = new Result();
        try {
            if (r.recordId == null) {
                out.success = false;
                out.errorMessage = 'Record Id is required';
                return out;
            }
            if (String.isBlank(r.templateName)) {
                out.success = false;
                out.errorMessage = 'Template Name is required';
                return out;
            }

            String prefix = String.valueOf(r.recordId).substring(0, 3);
            String phone, name, objectType;
            Boolean optedOut = false;

            if (prefix == '003') {
                Contact c = [SELECT Name, Phone, MobilePhone, Do_Not_WhatsApp__c FROM Contact WHERE Id = :r.recordId LIMIT 1];
                name = c.Name;
                phone = String.isNotBlank(c.MobilePhone) ? c.MobilePhone : c.Phone;
                optedOut = c.Do_Not_WhatsApp__c;
                objectType = 'Contact';
            } else if (prefix == '00Q') {
                Lead l = [SELECT Name, Phone, MobilePhone, Do_Not_WhatsApp__c FROM Lead WHERE Id = :r.recordId LIMIT 1];
                name = l.Name;
                phone = String.isNotBlank(l.MobilePhone) ? l.MobilePhone : l.Phone;
                optedOut = l.Do_Not_WhatsApp__c;
                objectType = 'Lead';
            } else {
                out.success = false;
                out.errorMessage = 'Record type not supported. Use Contact or Lead.';
                return out;
            }

            if (optedOut) {
                out.success = false;
                out.errorMessage = name + ' has Do Not WhatsApp checked.';
                return out;
            }
            if (String.isBlank(phone)) {
                out.success = false;
                out.errorMessage = name + ' has no phone number on file.';
                return out;
            }

            String lang = String.isNotBlank(r.language) ? r.language : 'en';
            Map<String, String> vars = new Map<String, String>();
            if (String.isNotBlank(r.variable1)) vars.put('1', r.variable1);
            if (String.isNotBlank(r.variable2)) vars.put('2', r.variable2);
            if (String.isNotBlank(r.variable3)) vars.put('3', r.variable3);
            if (String.isNotBlank(r.variable4)) vars.put('4', r.variable4);
            if (String.isNotBlank(r.variable5)) vars.put('5', r.variable5);

            ZaptiloAPI.SendResult api = ZaptiloAPI.sendTemplate(normalizePhone(phone), r.templateName, lang, vars);

            WhatsApp_Message__c log = new WhatsApp_Message__c(
                Phone__c = normalizePhone(phone),
                Direction__c = 'Outbound',
                Template_Name__c = r.templateName,
                Status__c = String.isBlank(api.status) ? 'sent' : api.status,
                External_Id__c = api.externalId
            );
            if (objectType == 'Contact') log.Contact__c = r.recordId;
            if (objectType == 'Lead') log.Lead__c = r.recordId;
            insert log;

            out.success = true;
            out.messageLogId = log.Id;
            out.externalId = api.externalId;
        } catch (Exception e) {
            out.success = false;
            out.errorMessage = e.getMessage();
        }
        return out;
    }

    private static String normalizePhone(String raw) {
        if (String.isBlank(raw)) return raw;
        String stripped = raw.replaceAll('[\\s\\-\\(\\)]', '');
        if (!stripped.startsWith('+')) stripped = '+' + stripped;
        return stripped;
    }
}
