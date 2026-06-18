import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import loadConfig from '@salesforce/apex/ZaptiloSettingsController.loadConfig';
import saveConfig from '@salesforce/apex/ZaptiloSettingsController.saveConfig';
import testConnection from '@salesforce/apex/ZaptiloSettingsController.testConnection';

export default class ZaptiloSettings extends LightningElement {
    @track loading = true;
    @track saving = false;
    @track testing = false;
    @track configured = false;
    @track apiToken = '';
    @track baseUrl = 'https://web.zaptilo.ai';
    @track defaultWaba = '';
    @track maskedTokenHint = '';

    connectedCallback() {
        this.bootstrap();
    }

    async bootstrap() {
        try {
            const dto = await loadConfig();
            this.configured = !!dto.configured;
            if (this.configured) {
                this.maskedTokenHint = dto.apiToken;
                this.apiToken = '';
            }
            this.baseUrl = dto.baseUrl || 'https://web.zaptilo.ai';
            this.defaultWaba = dto.defaultWaba || '';
        } catch (e) {
            this.toast('Load failed', this.errMsg(e), 'error');
        } finally {
            this.loading = false;
        }
    }

    handleTokenChange(e) { this.apiToken = e.target.value; }
    handleBaseUrlChange(e) { this.baseUrl = e.target.value; }
    handleWabaChange(e) { this.defaultWaba = e.target.value; }

    async handleSave() {
        this.saving = true;
        try {
            await saveConfig({
                apiToken: this.apiToken,
                baseUrl: this.baseUrl,
                defaultWaba: this.defaultWaba
            });
            this.toast('Saved', 'Zaptilo configuration updated.', 'success');
            await this.bootstrap();
        } catch (e) {
            this.toast('Save failed', this.errMsg(e), 'error');
        } finally {
            this.saving = false;
        }
    }

    async handleTest() {
        this.testing = true;
        try {
            await testConnection();
            this.toast('Connection OK', 'Zaptilo accepted your API token.', 'success');
        } catch (e) {
            this.toast('Connection failed', this.errMsg(e), 'error', 'sticky');
        } finally {
            this.testing = false;
        }
    }

    toast(title, message, variant, mode) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant, mode: mode || 'dismissable' }));
    }

    errMsg(e) {
        return e?.body?.message || e?.message || 'Unknown error';
    }
}
