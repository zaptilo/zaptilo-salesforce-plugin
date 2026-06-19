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
        // For Case / Opportunity / Account, the actual person we're texting may be a related Contact.
        // Tracking that id here lets us thread the message log to the Contact for activity history.
        @AuraEnabled public String linkedContactId;
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
                FROM Contact WHERE Id = :rid LIMIT 1
            ];
            ctx.name = c.Name;
            ctx.phone = String.isNotBlank(c.MobilePhone) ? c.MobilePhone : c.Phone;
            ctx.optedOut = c.Do_Not_WhatsApp__c;

        } else if (prefix == '00Q') {
            ctx.objectType = 'Lead';
            Lead l = [
                SELECT Name, Phone, MobilePhone, Do_Not_WhatsApp__c
                FROM Lead WHERE Id = :rid LIMIT 1
            ];
            ctx.name = l.Name;
            ctx.phone = String.isNotBlank(l.MobilePhone) ? l.MobilePhone : l.Phone;
            ctx.optedOut = l.Do_Not_WhatsApp__c;

        } else if (prefix == '001') {
            ctx.objectType = 'Account';
            Account a = [SELECT Name, Phone FROM Account WHERE Id = :rid LIMIT 1];
            ctx.name = a.Name;
            ctx.phone = a.Phone;
            ctx.optedOut = false; // Accounts don't carry the opt-out flag; rely on linked Contact's flag at agent's discretion.

        } else if (prefix == '500') {
            // Case → message the Case's Contact. Phone + opt-out come from that Contact.
            ctx.objectType = 'Case';
            Case cs = [
                SELECT CaseNumber, ContactId, Contact.Name, Contact.Phone, Contact.MobilePhone, Contact.Do_Not_WhatsApp__c
                FROM Case WHERE Id = :rid LIMIT 1
            ];
            if (cs.ContactId == null) {
                throw new AuraHandledException(
                    'This Case has no linked Contact. Add a Contact to the Case to send WhatsApp.'
                );
            }
            ctx.name = cs.Contact.Name + ' (Case ' + cs.CaseNumber + ')';
            ctx.phone = String.isNotBlank(cs.Contact.MobilePhone) ? cs.Contact.MobilePhone : cs.Contact.Phone;
            ctx.optedOut = cs.Contact.Do_Not_WhatsApp__c;
            ctx.linkedContactId = cs.ContactId;

        } else if (prefix == '006') {
            // Opportunity → message the primary OpportunityContactRole's Contact.
            ctx.objectType = 'Opportunity';
            Opportunity opp = [SELECT Name FROM Opportunity WHERE Id = :rid LIMIT 1];

            List<OpportunityContactRole> roles = [
                SELECT ContactId, IsPrimary, Contact.Name, Contact.Phone, Contact.MobilePhone, Contact.Do_Not_WhatsApp__c
                FROM OpportunityContactRole
                WHERE OpportunityId = :rid
                ORDER BY IsPrimary DESC NULLS LAST
                LIMIT 1
            ];
            if (roles.isEmpty()) {
                throw new AuraHandledException(
                    'This Opportunity has no Contact Roles. Add at least one Contact to send WhatsApp.'
                );
            }
            OpportunityContactRole r = roles[0];
            ctx.name = r.Contact.Name + ' (' + opp.Name + ')';
            ctx.phone = String.isNotBlank(r.Contact.MobilePhone) ? r.Contact.MobilePhone : r.Contact.Phone;
            ctx.optedOut = r.Contact.Do_Not_WhatsApp__c;
            ctx.linkedContactId = r.ContactId;

        } else {
            throw new AuraHandledException(
                'Send WhatsApp is not available on this object type.'
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
            } else if (String.isNotBlank(ctx.linkedContactId)) {
                // Case / Opportunity → thread the log on the actual person we texted.
                log.Contact__c = ctx.linkedContactId;
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
