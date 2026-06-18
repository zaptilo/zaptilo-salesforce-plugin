/**
 * Unit tests for ZaptiloAPI and ZaptiloSendController. Mocks the HTTP layer
 * so no real Zaptilo calls happen in CI / package validation.
 */
@IsTest
private class ZaptiloAPITest {

    private static void seedConfig() {
        Zaptilo_Config__c c = new Zaptilo_Config__c();
        c.SetupOwnerId = UserInfo.getOrganizationId();
        c.API_Token__c = 'test-token-1234';
        c.Base_URL__c = 'https://web.zaptilo.ai';
        insert c;
    }

    private class OkSendMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"statusCode":200,"data":{"id":"wamid.HBgM12345","status":"sent"}}');
            return res;
        }
    }

    private class TemplatesListMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"statusCode":200,"data":[{"name":"order_confirmation","language":"en","status":"APPROVED"}]}');
            return res;
        }
    }

    private class FailMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setBody('{"statusCode":401,"message":"Unauthorized"}');
            return res;
        }
    }

    @IsTest
    static void sendTemplate_happyPath() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new OkSendMock());

        Test.startTest();
        ZaptiloAPI.SendResult r = ZaptiloAPI.sendTemplate(
            '+919876543210',
            'order_confirmation',
            'en',
            new Map<String, String>{ '1' => 'Acme', '2' => 'AB123' }
        );
        Test.stopTest();

        System.assert(r.success, 'Expected success on 200 response');
        System.assertEquals('wamid.HBgM12345', r.externalId);
    }

    @IsTest
    static void sendText_happyPath() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new OkSendMock());

        Test.startTest();
        ZaptiloAPI.SendResult r = ZaptiloAPI.sendText('+919876543210', 'Hello');
        Test.stopTest();

        System.assert(r.success);
    }

    @IsTest
    static void sendMedia_happyPath() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new OkSendMock());

        Test.startTest();
        ZaptiloAPI.SendResult r = ZaptiloAPI.sendMedia(
            '+919876543210',
            'image',
            'https://example.com/x.jpg',
            'x.jpg',
            'caption'
        );
        Test.stopTest();

        System.assert(r.success);
    }

    @IsTest
    static void listTemplates_returnsArray() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new TemplatesListMock());

        Test.startTest();
        List<Object> tpl = ZaptiloAPI.listTemplates();
        Test.stopTest();

        System.assertEquals(1, tpl.size());
    }

    @IsTest
    static void sendTemplate_throwsOnAuthFail() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new FailMock());

        Test.startTest();
        try {
            ZaptiloAPI.sendTemplate('+919876543210', 'x', 'en', null);
            System.assert(false, 'Should have thrown');
        } catch (ZaptiloAPI.ZaptiloException e) {
            System.assert(e.getMessage().contains('401'));
        }
        Test.stopTest();
    }

    @IsTest
    static void send_throwsWhenNotConfigured() {
        // No config inserted — should throw
        Test.startTest();
        try {
            ZaptiloAPI.sendText('+91', 'x');
            System.assert(false, 'Should have thrown for missing config');
        } catch (ZaptiloAPI.ZaptiloException e) {
            System.assert(e.getMessage().contains('not configured'));
        }
        Test.stopTest();
    }

    @IsTest
    static void sendController_endToEndContact() {
        seedConfig();
        Contact c = new Contact(LastName = 'Test', MobilePhone = '+919876543210');
        insert c;

        Test.setMock(HttpCalloutMock.class, new OkSendMock());

        Test.startTest();
        String logId = ZaptiloSendController.sendTemplate(
            c.Id,
            'order_confirmation',
            'en',
            new Map<String, String>{ '1' => 'Acme' }
        );
        Test.stopTest();

        System.assertNotEquals(null, logId);
        WhatsApp_Message__c log = [SELECT Direction__c, Template_Name__c, External_Id__c FROM WhatsApp_Message__c WHERE Id = :logId];
        System.assertEquals('Outbound', log.Direction__c);
        System.assertEquals('order_confirmation', log.Template_Name__c);
        System.assertEquals('wamid.HBgM12345', log.External_Id__c);
    }

    @IsTest
    static void sendController_blocksOptedOut() {
        seedConfig();
        Contact c = new Contact(
            LastName = 'OptOut',
            MobilePhone = '+919876543210',
            Do_Not_WhatsApp__c = true
        );
        insert c;

        Test.startTest();
        try {
            ZaptiloSendController.sendTemplate(c.Id, 'x', 'en', null);
            System.assert(false, 'Should have thrown for opted-out contact');
        } catch (AuraHandledException e) {
            // expected
        }
        Test.stopTest();
    }

    @IsTest
    static void settings_saveAndLoad() {
        Test.startTest();
        ZaptiloSettingsController.saveConfig('new-token-9999', 'https://web.zaptilo.ai', '');
        ZaptiloSettingsController.ConfigDTO dto = ZaptiloSettingsController.loadConfig();
        Test.stopTest();

        System.assert(dto.configured);
        System.assert(dto.apiToken.startsWith('••'));
        System.assert(dto.apiToken.endsWith('9999'));
    }
}
