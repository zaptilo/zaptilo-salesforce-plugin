/**
 * Apex backing for the zaptiloSettings LWC.
 * Reads / writes the org-default Zaptilo_Config__c record.
 */
public with sharing class ZaptiloSettingsController {

    public class ConfigDTO {
        @AuraEnabled public String apiToken;
        @AuraEnabled public String baseUrl;
        @AuraEnabled public String defaultWaba;
        @AuraEnabled public Boolean configured;
    }

    @AuraEnabled(cacheable=true)
    public static ConfigDTO loadConfig() {
        Zaptilo_Config__c c = Zaptilo_Config__c.getOrgDefaults();
        ConfigDTO dto = new ConfigDTO();
        if (c != null && String.isNotBlank(c.API_Token__c)) {
            // Mask the token in the read response — UI shows "••••••••XXXX"
            String tok = c.API_Token__c;
            dto.apiToken = tok.length() > 4 ? '••••••••' + tok.right(4) : '••••';
            dto.baseUrl = c.Base_URL__c;
            dto.defaultWaba = c.Default_WABA__c;
            dto.configured = true;
        } else {
            dto.baseUrl = 'https://web.zaptilo.ai';
            dto.configured = false;
        }
        return dto;
    }

    @AuraEnabled
    public static void saveConfig(String apiToken, String baseUrl, String defaultWaba) {
        if (!Schema.sObjectType.Zaptilo_Config__c.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to update Zaptilo configuration.');
        }
        Zaptilo_Config__c c = Zaptilo_Config__c.getOrgDefaults();
        if (c == null) {
            c = new Zaptilo_Config__c();
            c.SetupOwnerId = UserInfo.getOrganizationId();
        }
        // Only overwrite the token if the user typed a new one (LWC sends blank to mean "leave alone")
        if (String.isNotBlank(apiToken) && !apiToken.startsWith('••')) {
            c.API_Token__c = apiToken;
        }
        c.Base_URL__c = String.isNotBlank(baseUrl) ? baseUrl : 'https://web.zaptilo.ai';
        c.Default_WABA__c = defaultWaba;
        upsert c;
    }

    /**
     * Round-trip the configured API token against /api/verify to confirm it works.
     * UI calls this after the user pastes a token to give them immediate feedback.
     */
    @AuraEnabled
    public static String testConnection() {
        try {
            // Reuse the templates endpoint as a cheap auth check — returns 401 on bad token,
            // 200 with an array (possibly empty) on good token.
            ZaptiloAPI.listTemplates();
            return 'OK';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
