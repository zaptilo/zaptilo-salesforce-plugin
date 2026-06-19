import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getRecordContext from '@salesforce/apex/ZaptiloSendController.getRecordContext';
import getTemplates from '@salesforce/apex/ZaptiloSendController.getTemplates';
import sendTemplate from '@salesforce/apex/ZaptiloSendController.sendTemplate';

// Bumped each time we redeploy this file — confirms which version the browser actually loaded.
const ZAPTILO_BUILD = 'v0.1-build12';

// Reject the promise after `ms` so a hung Apex callout never freezes the modal forever.
function withTimeout(promise, ms, label) {
    return new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error(`${label} took longer than ${ms}ms — aborted`)), ms);
        promise.then(
            (value) => { clearTimeout(timer); resolve(value); },
            (err) => { clearTimeout(timer); reject(err); }
        );
    });
}
// eslint-disable-next-line no-console
console.log('[Zaptilo] zaptiloSendModal module loaded —', ZAPTILO_BUILD);

// Zaptilo wraps the Meta template shape inside a stringified `metadata` field.
// Parse it once, cache parsed result on the template object so we don't re-parse on every render.
function parsedMetadata(template) {
    if (!template) return null;
    if (template._parsedMetadata !== undefined) return template._parsedMetadata;
    if (typeof template.metadata === 'string' && template.metadata.length > 0) {
        try {
            template._parsedMetadata = JSON.parse(template.metadata);
        } catch (e) {
            template._parsedMetadata = null;
        }
    } else if (template.metadata && typeof template.metadata === 'object') {
        template._parsedMetadata = template.metadata;
    } else {
        template._parsedMetadata = null;
    }
    return template._parsedMetadata;
}

// Walk the template payload and find the BODY text (where {{N}} placeholders live).
function findBodyText(template) {
    if (!template) return '';
    const meta = parsedMetadata(template);
    const components = (meta && meta.components) || template.components || [];
    if (Array.isArray(components)) {
        for (const c of components) {
            const type = (c.type || '').toString().toUpperCase();
            if (type === 'BODY') {
                if (c.text) return c.text;
                if (c.body) return c.body;
            }
        }
    }
    if (template.body) return template.body;
    return '';
}

function findLanguageCode(template) {
    if (!template) return 'en';
    const meta = parsedMetadata(template);
    if (meta && meta.language) return meta.language;
    if (template.language) return template.language;
    return 'en';
}

function extractVariableIndexes(template) {
    const bodyText = findBodyText(template);
    const matches = bodyText.match(/{{\s*(\d+)\s*}}/g) || [];
    const indexes = new Set();
    for (const m of matches) {
        const n = parseInt(m.replace(/[^\d]/g, ''), 10);
        if (!isNaN(n)) indexes.add(n);
    }
    return Array.from(indexes).sort((a, b) => a - b);
}

export default class ZaptiloSendModal extends LightningElement {
    // recordId via getter/setter so we can react the moment the Quick Action framework injects it.
    _recordId;
    @api
    get recordId() { return this._recordId; }
    set recordId(value) {
        // eslint-disable-next-line no-console
        console.log('[Zaptilo] recordId setter called with', value);
        this._recordId = value;
        if (value && !this._bootstrapped) {
            this._bootstrapped = true;
            // eslint-disable-next-line no-console
            console.log('[Zaptilo] bootstrapping from setter, recordId=', value);
            this.bootstrap();
        }
    }

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
        // Belt-and-braces fallback: if for any reason the setter didn't fire, kick off here.
        if (!this._bootstrapped && this._recordId) {
            this._bootstrapped = true;
            // eslint-disable-next-line no-console
            console.log('[Zaptilo] bootstrapping from renderedCallback, recordId=', this._recordId);
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
            // eslint-disable-next-line no-console
            console.log('[Zaptilo] step 1: loading context…');
            this.context = await withTimeout(
                getRecordContext({ recordId: this.recordId }),
                15000,
                'Loading record context'
            );
            // eslint-disable-next-line no-console
            console.log('[Zaptilo] step 2: context loaded', this.context);
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('[Zaptilo] context load failed', e);
            this.errorMessage = this.errMsg(e);
            this.loading = false;
            return;
        }
        try {
            // eslint-disable-next-line no-console
            console.log('[Zaptilo] step 3: loading templates…');
            const raw = await withTimeout(getTemplates(), 20000, 'Loading templates');
            // eslint-disable-next-line no-console
            console.log('[Zaptilo] step 4: templates loaded count=', (raw || []).length);
            // Dump the first template fully so we can see Zaptilo's actual payload shape.
            if ((raw || []).length > 0) {
                // eslint-disable-next-line no-console
                console.log('[Zaptilo] first template payload:', JSON.stringify(raw[0], null, 2));
            }
            this.templates = raw || [];
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('[Zaptilo] template load failed', e);
            // Non-fatal — let the user know but still allow them to close the modal.
            this.errorMessage = 'Could not load templates: ' + this.errMsg(e);
        } finally {
            this.loading = false;
        }
    }

    get templateOptions() {
        return this.templates.map((t) => ({
            label: `${t.name} (${findLanguageCode(t)})`,
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
        this.language = findLanguageCode(t);
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
        const body = findBodyText(t);
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
