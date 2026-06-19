import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getRecordContext from '@salesforce/apex/ZaptiloSendController.getRecordContext';
import getTemplates from '@salesforce/apex/ZaptiloSendController.getTemplates';
import sendTemplate from '@salesforce/apex/ZaptiloSendController.sendTemplate';

// Bumped each time we redeploy this file — confirms which version the browser actually loaded.
const ZAPTILO_BUILD = 'v0.1-build8';
// eslint-disable-next-line no-console
console.log('[Zaptilo] zaptiloSendModal module loaded —', ZAPTILO_BUILD);

// Look at every component of a WhatsApp template and find the BODY text, then count distinct {{N}} placeholders.
function extractVariableIndexes(template) {
    if (!template) return [];
    const components = template.components || [];
    let bodyText = '';
    for (const c of components) {
        const type = (c.type || '').toString().toUpperCase();
        if (type === 'BODY') {
            bodyText = c.text || c.body || '';
            break;
        }
    }
    // Some Zaptilo workspaces store the body in a flat `body` field instead of `components`.
    if (!bodyText && template.body) bodyText = template.body;

    const matches = bodyText.match(/{{\s*(\d+)\s*}}/g) || [];
    const indexes = new Set();
    for (const m of matches) {
        const n = parseInt(m.replace(/[^\d]/g, ''), 10);
        if (!isNaN(n)) indexes.add(n);
    }
    return Array.from(indexes).sort((a, b) => a - b);
}

export default class ZaptiloSendModal extends LightningElement {
    @api recordId;

    @track loading = true;
    @track sending = false;
    @track context;
    @track templates = [];           // full template objects, raw from Zaptilo
    @track selectedTemplate = '';
    @track language = 'en';
    @track variables = {};
    @track variableInputs = [];      // [{ index: '1', label: 'Variable 1' }, ...] — dynamic per template
    @track templatePreview = '';     // body text with current variable values substituted
    @track errorMessage = '';
    _bootstrapped = false;

    connectedCallback() {
        // eslint-disable-next-line no-console
        console.log('[Zaptilo] modal connected, recordId=', this.recordId);
    }

    renderedCallback() {
        // The Quick Action framework sets @api recordId AFTER connectedCallback fires.
        // Bootstrap on the first render that has a recordId present.
        if (!this._bootstrapped && this.recordId) {
            this._bootstrapped = true;
            // eslint-disable-next-line no-console
            console.log('[Zaptilo] bootstrapping with recordId=', this.recordId);
            this.bootstrap();
        }
    }

    async bootstrap() {
        if (!this.recordId) {
            this.errorMessage = 'No record id was passed to the Send WhatsApp action.';
            this.loading = false;
            return;
        }
        try {
            this.context = await getRecordContext({ recordId: this.recordId });
            try {
                const raw = await getTemplates();
                // eslint-disable-next-line no-console
                console.log('[Zaptilo] templates raw=', JSON.stringify(raw));
                this.templates = raw || [];
            } catch (e) {
                this.errorMessage = 'Could not load templates: ' + this.errMsg(e);
            }
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('[Zaptilo] bootstrap error', e);
            this.errorMessage = this.errMsg(e);
        } finally {
            this.loading = false;
        }
    }

    get templateOptions() {
        return this.templates.map((t) => ({
            label: `${t.name} (${t.language || 'en'})`,
            value: t.name
        }));
    }

    get selectedTemplateObj() {
        return this.templates.find((t) => t.name === this.selectedTemplate);
    }

    get hasVariableInputs() {
        return this.variableInputs.length > 0;
    }

    get hasNoVariableInputs() {
        return !!this.selectedTemplate && this.variableInputs.length === 0;
    }

    get canSend() {
        return (
            !this.sending &&
            this.context &&
            this.context.phone &&
            !this.context.optedOut &&
            this.selectedTemplate
        );
    }

    get sendDisabled() {
        return !this.canSend;
    }

    get sendButtonLabel() {
        return this.sending ? 'Sending…' : 'Send WhatsApp';
    }

    get optedOutMessage() {
        if (!this.context) return null;
        if (this.context.optedOut) {
            return `${this.context.name} has Do Not WhatsApp checked. Uncheck the field on the record to enable sending.`;
        }
        if (!this.context.phone) {
            return `${this.context.name} has no phone number on file. Add a phone or mobile to enable sending.`;
        }
        return null;
    }

    handleTemplateChange(event) {
        this.selectedTemplate = event.detail.value;
        const t = this.selectedTemplateObj;
        this.language = (t && t.language) || 'en';
        this.variables = {};

        // Inspect the template's body and build one input per {{N}} placeholder.
        const indexes = extractVariableIndexes(t);
        this.variableInputs = indexes.map((n) => ({
            index: String(n),
            label: `Variable ${n}`,
            key: `var-${this.selectedTemplate}-${n}`
        }));
        this.refreshPreview();
    }

    handleVariableChange(event) {
        const idx = event.target.dataset.index;
        this.variables = { ...this.variables, [idx]: event.target.value };
        this.refreshPreview();
    }

    refreshPreview() {
        const t = this.selectedTemplateObj;
        if (!t) { this.templatePreview = ''; return; }
        let body = '';
        const comps = t.components || [];
        for (const c of comps) {
            const type = (c.type || '').toString().toUpperCase();
            if (type === 'BODY') { body = c.text || c.body || ''; break; }
        }
        if (!body && t.body) body = t.body;
        this.templatePreview = body.replace(/{{\s*(\d+)\s*}}/g, (_, n) => {
            return this.variables[n] || `{{${n}}}`;
        });
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleSend() {
        if (!this.canSend) return;
        this.sending = true;
        try {
            await sendTemplate({
                recordId: this.recordId,
                templateName: this.selectedTemplate,
                language: this.language,
                variables: this.variables
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'WhatsApp sent',
                    message: `Sent ${this.selectedTemplate} to ${this.context.name}.`,
                    variant: 'success'
                })
            );
            this.handleClose();
        } catch (e) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Send failed',
                    message: this.errMsg(e),
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.sending = false;
        }
    }

    errMsg(e) {
        return e?.body?.message || e?.message || 'Unknown error';
    }
}
