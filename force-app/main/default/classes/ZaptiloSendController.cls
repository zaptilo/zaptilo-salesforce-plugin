/**
 * Apex backing for the zaptiloSendModal Lightning Web Component.
 * Exposes record context, template list, and the send action.
 */
public with sharing class ZaptiloSendController {

    public class RecordContext {
        @AuraEnabled public String recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String phone;
        @AuraEnabled public Boolean optedOut;
        @AuraEnabled public String objectType;
    }

    /**
     * Loads the displayable name, phone, and opt-out status for any Contact or Lead.
     * Used by the LWC to render the modal header and gate the Send button.
     */
    @AuraEnabled(cacheable=true)
    public static RecordContext getRecordContext(String recordId) {
        if (String.isBlank(recordId)) {
            return null;
        }
        RecordContext ctx = new RecordContext();
        ctx.recordId = recordId;

        Id rid = (Id) recordId;
        String prefix = String.valueOf(rid).substring(0, 3);

        if (prefix == '003') {
            ctx.objectType = 'Contact';
            Contact c = [
                SELECT Name, Phone, MobilePhone, Do_Not_WhatsApp__c
                FROM Contact
                WHERE Id = :rid
                LIMIT 1
            ];
            ctx.name = c.Name;
            ctx.phone = String.isNotBlank(c.MobilePhone) ? c.MobilePhone : c.Phone;
            ctx.optedOut = c.Do_Not_WhatsApp__c;
        } else if (prefix == '00Q') {
            ctx.objectType = 'Lead';
            Lead l = [
                SELECT Name, Phone, MobilePhone, Do_Not_WhatsApp__c
                FROM Lead
                WHERE Id = :rid
                LIMIT 1
            ];
            ctx.name = l.Name;
            ctx.phone = String.isNotBlank(l.MobilePhone) ? l.MobilePhone : l.Phone;
            ctx.optedOut = l.Do_Not_WhatsApp__c;
        } else {
            throw new AuraHandledException(
                'Send WhatsApp is only available on Contact and Lead records in this release.'
            );
        }

        return ctx;
    }

    /**
     * Returns the list of approved WhatsApp templates from the Zaptilo workspace.
     * Cached on the client between modal opens.
     */
    @AuraEnabled
    public static List<Object> getTemplates() {
        try {
            return ZaptiloAPI.listTemplates();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Sends a template message via Zaptilo and logs a WhatsApp_Message__c record.
     * Throws AuraHandledException on opt-out, missing phone, or API error.
     */
    @AuraEnabled
    public static String sendTemplate(
        String recordId,
        String templateName,
        String language,
        Map<String, String> variables
    ) {
        RecordContext ctx = getRecordContext(recordId);
        if (ctx == null || String.isBlank(ctx.phone)) {
            throw new AuraHandledException('No phone number found on this record.');
        }
        if (ctx.optedOut) {
            throw new AuraHandledException(
                ctx.name + ' has Do Not WhatsApp set. Uncheck the field to send.'
            );
        }

        try {
            ZaptiloAPI.SendResult result = ZaptiloAPI.sendTemplate(
                normalizePhone(ctx.phone),
                templateName,
                language,
                variables
            );

            WhatsApp_Message__c log = new WhatsApp_Message__c(
                Phone__c = normalizePhone(ctx.phone),
                Direction__c = 'Outbound',
                Template_Name__c = templateName,
                Status__c = result.success ? (String.isBlank(result.status) ? 'sent' : result.status) : 'failed',
                External_Id__c = result.externalId
            );
            if (ctx.objectType == 'Contact') {
                log.Contact__c = recordId;
            } else if (ctx.objectType == 'Lead') {
                log.Lead__c = recordId;
            }
            insert log;

            return log.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Minimal E.164 normalizer: strips spaces / dashes / parens. Does NOT
     * infer country code — admins should store phones with the leading '+'.
     */
    private static String normalizePhone(String raw) {
        if (String.isBlank(raw)) return raw;
        String stripped = raw.replaceAll('[\\s\\-\\(\\)]', '');
        if (!stripped.startsWith('+')) {
            stripped = '+' + stripped;
        }
        return stripped;
    }
}
