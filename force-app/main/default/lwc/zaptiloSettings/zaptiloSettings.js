import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import loadConfig from '@salesforce/apex/ZaptiloSettingsController.loadConfig';
import saveConfig from '@salesforce/apex/ZaptiloSettingsController.saveConfig';
import testConnection from '@salesforce/apex/ZaptiloSettingsController.testConnection';
import getWhatsappConnections from '@salesforce/apex/ZaptiloSettingsController.getWhatsappConnections';

export default class ZaptiloSettings extends LightningElement {
    @track loading = true;
    @track saving = false;
    @track testing = false;
    @track configured = false;
    @track apiToken = '';
    @track baseUrl = 'https://web.zaptilo.ai';
    @track defaultWaba = '';
    @track maskedTokenHint = '';
    @track wabaOptions = [];           // [{label, value}] for the lightning-combobox
    @track wabaLoadError = '';

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

            // If a token is configured, fetch the WABA list so admins get a dropdown.
            if (this.configured) {
                await this.loadWabaList();
            }
        } catch (e) {
            this.toast('Load failed', this.errMsg(e), 'error');
        } finally {
            this.loading = false;
        }
    }

    async loadWabaList() {
        this.wabaLoadError = '';
        try {
            const conns = await getWhatsappConnections();
            this.wabaOptions = (conns || []).map((c) => ({
                label: this.describeWaba(c),
                value: c.uuid || c.id || ''
            })).filter((o) => o.value);
            if (this.wabaOptions.length === 0) {
                this.wabaLoadError = 'No WhatsApp connections found in this Zaptilo workspace.';
            }
        } catch (e) {
            this.wabaLoadError = 'Could not load WABA list: ' + this.errMsg(e);
        }
    }

    describeWaba(c) {
        const name = c.name || c.display_name || c.label || c.phone_number || 'WhatsApp connection';
        const phone = c.phone_number || c.phone || '';
        const type = c.type ? ` • ${c.type}` : '';
        return phone ? `${name} (${phone})${type}` : `${name}${type}`;
    }

    get hasWabaList() {
        return this.wabaOptions && this.wabaOptions.length > 0;
    }

    handleTokenChange(e) { this.apiToken = e.target.value; }
    handleBaseUrlChange(e) { this.baseUrl = e.target.value; }
    handleWabaChange(e) { this.defaultWaba = e.detail ? e.detail.value : e.target.value; }

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
