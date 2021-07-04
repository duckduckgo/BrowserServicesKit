 (function(){function r(e,n,t){function o(i,f){if(!n[i]){if(!e[i]){var c="function"==typeof require&&require;if(!f&&c)return c(i,!0);if(u)return u(i,!0);var a=new Error("Cannot find module '"+i+"'");throw a.code="MODULE_NOT_FOUND",a}var p=n[i]={exports:{}};e[i][0].call(p.exports,function(r){var n=e[i][1][r];return o(n||r)},p,p.exports,r,e,n,t)}return n[i].exports}for(var u="function"==typeof require&&require,i=0;i<t.length;i++)o(t[i]);return o}return r})()({1:[function(require,module,exports){
 "use strict";

 const {
   isApp,
   formatAddress,
   getDaxBoundingBox,
   safeExecute,
   escapeXML
 } = require('./autofill-utils');

 class DDGAutofill {
   constructor(input, associatedForm, getAddresses, refreshAlias, addresses) {
     const shadow = document.createElement('ddg-autofill').attachShadow({
       mode: 'closed'
     });
     this.host = shadow.host;
     this.input = input;
     this.associatedForm = associatedForm;
     this.addresses = addresses;
     this.animationFrame = null;
     const includeStyles = isApp ? "<style>".concat(require('./styles/DDGAutofill-styles.js'), "</style>") : "<link rel=\"stylesheet\" href=\"".concat(chrome.runtime.getURL('public/css/autofill.css'), "\" crossorigin=\"anonymous\">");
     shadow.innerHTML = "\n".concat(includeStyles, "\n<div class=\"wrapper\">\n    <div class=\"tooltip\" hidden>\n        <button class=\"tooltip__button tooltip__button--secondary js-use-personal\">\n            <span class=\"tooltip__button__primary-text\">\n                Use <span class=\"js-address\">").concat(formatAddress(escapeXML(this.addresses.personalAddress)), "</span>\n            </span>\n            <span class=\"tooltip__button__secondary-text\">Blocks email trackers</span>\n        </button>\n        <button class=\"tooltip__button tooltip__button--primary js-use-private\">\n            <span class=\"tooltip__button__primary-text\">Use a Private Address</span>\n            <span class=\"tooltip__button__secondary-text\">Blocks email trackers and hides your address</span>\n        </button>\n    </div>\n</div>");
     this.wrapper = shadow.querySelector('.wrapper');
     this.tooltip = shadow.querySelector('.tooltip');
     this.usePersonalButton = shadow.querySelector('.js-use-personal');
     this.usePrivateButton = shadow.querySelector('.js-use-private');
     this.addressEl = shadow.querySelector('.js-address');
     this.stylesheet = shadow.querySelector('link, style'); // Un-hide once the style is loaded, to avoid flashing unstyled content

     this.stylesheet.addEventListener('load', () => this.tooltip.removeAttribute('hidden'));

     this.updateAddresses = addresses => {
       if (addresses) {
         this.addresses = addresses;
         this.addressEl.textContent = formatAddress(addresses.personalAddress);
       }
     }; // Get the alias from the extension


     getAddresses().then(this.updateAddresses);
     this.top = 0;
     this.left = 0;
     this.transformRuleIndex = null;

     this.updatePosition = ({
       left,
       top
     }) => {
       // If the stylesheet is not loaded wait for load (Chrome bug)
       if (!shadow.styleSheets.length) return this.stylesheet.addEventListener('load', this.checkPosition);
       this.left = left;
       this.top = top;

       if (this.transformRuleIndex && shadow.styleSheets[this.transformRuleIndex]) {
         // If we have already set the rule, remove it…
         shadow.styleSheets[0].deleteRule(this.transformRuleIndex);
       } else {
         // …otherwise, set the index as the very last rule
         this.transformRuleIndex = shadow.styleSheets[0].rules.length;
       }

       const newRule = ".wrapper {transform: translate(".concat(left, "px, ").concat(top, "px);}");
       shadow.styleSheets[0].insertRule(newRule, this.transformRuleIndex);
     };

     this.append = () => document.body.appendChild(shadow.host);

     this.append();

     this.lift = () => {
       this.left = null;
       this.top = null;
       document.body.removeChild(this.host);
     };

     this.remove = () => {
       window.removeEventListener('scroll', this.checkPosition, {
         passive: true,
         capture: true
       });
       this.resObs.disconnect();
       this.mutObs.disconnect();
       this.lift();
     };

     this.checkPosition = () => {
       if (this.animationFrame) {
         window.cancelAnimationFrame(this.animationFrame);
       }

       this.animationFrame = window.requestAnimationFrame(() => {
         const {
           left,
           bottom
         } = getDaxBoundingBox(this.input);

         if (left !== this.left || bottom !== this.top) {
           this.updatePosition({
             left,
             top: bottom
           });
         }

         this.animationFrame = null;
       });
     };

     this.resObs = new ResizeObserver(entries => entries.forEach(this.checkPosition));
     this.resObs.observe(document.body);
     this.count = 0;

     this.ensureIsLastInDOM = () => {
       // If DDG el is not the last in the doc, move it there
       if (document.body.lastElementChild !== this.host) {
         this.lift(); // Try up to 5 times to avoid infinite loop in case someone is doing the same

         if (this.count < 15) {
           this.append();
           this.checkPosition();
           this.count++;
         } else {
           // Reset count so we can resume normal flow
           this.count = 0;
           console.info("DDG autofill bailing out");
         }
       }
     };

     this.mutObs = new MutationObserver(mutationList => {
       for (const mutationRecord of mutationList) {
         if (mutationRecord.type === 'childList') {
           // Only check added nodes
           mutationRecord.addedNodes.forEach(el => {
             if (el.nodeName === 'DDG-AUTOFILL') return;
             this.ensureIsLastInDOM();
           });
         }
       }

       this.checkPosition();
     });
     this.mutObs.observe(document.body, {
       childList: true,
       subtree: true,
       attributes: true
     });
     window.addEventListener('scroll', this.checkPosition, {
       passive: true,
       capture: true
     });
     this.usePersonalButton.addEventListener('click', e => {
       if (!e.isTrusted) return;
       e.stopImmediatePropagation();
       safeExecute(this.usePersonalButton, () => {
         this.associatedForm.autofill(formatAddress(this.addresses.personalAddress));
       });
     });
     this.usePrivateButton.addEventListener('click', e => {
       if (!e.isTrusted) return;
       e.stopImmediatePropagation();
       safeExecute(this.usePersonalButton, () => {
         this.associatedForm.autofill(formatAddress(this.addresses.privateAddress));
         refreshAlias();
       });
     });
   }

 }

 module.exports = DDGAutofill;

 },{"./autofill-utils":7,"./styles/DDGAutofill-styles.js":12}],2:[function(require,module,exports){
 "use strict";

 const DDGAutofill = require('./DDGAutofill');

 const {
   isApp,
   notifyWebApp,
   isDDGApp,
   isAndroid,
   isDDGDomain,
   sendAndWaitForAnswer,
   setValue,
   formatAddress
 } = require('./autofill-utils');

 const {
   wkSend,
   wkSendAndWait
 } = require('./appleDeviceUtils/appleDeviceUtils');

 const scanForInputs = require('./scanForInputs.js');

 const SIGN_IN_MSG = {
   signMeIn: true
 };

 const createAttachTooltip = (getAutofillData, refreshAlias, addresses) => (form, input) => {
   if (isDDGApp && !isApp) {
     form.activeInput = input;
     getAutofillData().then(alias => {
       if (alias) form.autofill(alias);else form.activeInput.focus();
     });
   } else {
     if (form.tooltip) return;
     form.activeInput = input;
     form.tooltip = new DDGAutofill(input, form, getAutofillData, refreshAlias, addresses);
     form.intObs.observe(input);
     window.addEventListener('mousedown', form.removeTooltip, {
       capture: true
     });
     window.addEventListener('input', form.removeTooltip, {
       once: true
     });
   }
 };

 let attempts = 0;

 class InterfacePrototype {
   init() {
     const start = () => {
       this.addDeviceListeners();
       this.setupAutofill();
     };

     if (document.readyState === 'complete') {
       start();
     } else {
       window.addEventListener('load', start);
     }
   }

   setupAutofill() {}

   getAddresses() {}

   refreshAlias() {}

   async trySigningIn() {
     if (isDDGDomain()) {
       if (attempts < 10) {
         attempts++;
         const data = await sendAndWaitForAnswer(SIGN_IN_MSG, 'addUserData'); // This call doesn't send a response, so we can't know if it succeeded

         this.storeUserData(data);
         this.setupAutofill({
           shouldLog: true
         });
       } else {
         console.warn('max attempts reached, bailing');
       }
     }
   }

   storeUserData() {}

   addDeviceListeners() {}

   addLogoutListener() {}

   attachTooltip() {}

   isDeviceSignedIn() {}

   getAlias() {}

 }

 class ExtensionInterface extends InterfacePrototype {
   constructor() {
     super();

     this.setupAutofill = ({
       shouldLog
     } = {
       shouldLog: false
     }) => {
       this.getAddresses().then(addresses => {
         if (addresses !== null && addresses !== void 0 && addresses.privateAddress && addresses !== null && addresses !== void 0 && addresses.personalAddress) {
           this.attachTooltip = createAttachTooltip(this.getAddresses, this.refreshAlias, addresses);
           notifyWebApp({
             deviceSignedIn: {
               value: true,
               shouldLog
             }
           });
           scanForInputs(this);
         } else {
           this.trySigningIn();
         }
       });
     };

     this.getAddresses = () => new Promise(resolve => chrome.runtime.sendMessage({
       getAddresses: true
     }, data => resolve(data)));

     this.refreshAlias = () => chrome.runtime.sendMessage({
       refreshAlias: true
     }, addresses => {
       this.addresses = addresses;
     });

     this.trySigningIn = () => {
       if (isDDGDomain()) {
         sendAndWaitForAnswer(SIGN_IN_MSG, 'addUserData').then(data => this.storeUserData(data));
       }
     };

     this.storeUserData = data => chrome.runtime.sendMessage(data);

     this.addDeviceListeners = () => {
       // Add contextual menu listeners
       let activeEl = null;
       document.addEventListener('contextmenu', e => {
         activeEl = e.target;
       });
       chrome.runtime.onMessage.addListener((message, sender) => {
         if (sender.id !== chrome.runtime.id) return;

         switch (message.type) {
           case 'ddgUserReady':
             this.setupAutofill({
               shouldLog: true
             });
             break;

           case 'contextualAutofill':
             setValue(activeEl, formatAddress(message.alias));
             activeEl.classList.add('ddg-autofilled');
             this.refreshAlias(); // If the user changes the alias, remove the decoration

             activeEl.addEventListener('input', e => e.target.classList.remove('ddg-autofilled'), {
               once: true
             });
             break;

           default:
             break;
         }
       });
     };

     this.addLogoutListener = handler => {
       // Cleanup on logout events
       chrome.runtime.onMessage.addListener((message, sender) => {
         if (sender.id === chrome.runtime.id && message.type === 'logout') {
           handler();
         }
       });
     };
   }

 }

 class AndroidInterface extends InterfacePrototype {
   constructor() {
     super();

     this.getAlias = () => sendAndWaitForAnswer(() => window.EmailInterface.showTooltip(), 'getAliasResponse').then(({
       alias
     }) => alias);

     this.isDeviceSignedIn = () => new Promise(resolve => {
       resolve(window.EmailInterface.isSignedIn() === 'true');
     });

     this.setupAutofill = ({
       shouldLog
     } = {
       shouldLog: false
     }) => {
       this.isDeviceSignedIn().then(signedIn => {
         if (signedIn) {
           notifyWebApp({
             deviceSignedIn: {
               value: true,
               shouldLog
             }
           });
           scanForInputs(this);
         } else {
           this.trySigningIn();
         }
       });
     };

     this.storeUserData = ({
       addUserData: {
         token,
         userName
       }
     }) => window.EmailInterface.storeCredentials(token, userName);

     this.attachTooltip = createAttachTooltip(this.getAlias);
   }

 }

 class AppleDeviceInterface extends InterfacePrototype {
   constructor() {
     super();

     if (isDDGDomain()) {
       // Tell the web app whether we're in the app
       notifyWebApp({
         isApp
       });
     }

     this.setupAutofill = async ({
       shouldLog
     } = {
       shouldLog: false
     }) => {
       const signedIn = await this.isDeviceSignedIn();

       if (signedIn) {
         this.attachTooltip = createAttachTooltip(this.getAddresses, this.refreshAlias, {});
         notifyWebApp({
           deviceSignedIn: {
             value: true,
             shouldLog
           }
         });
         scanForInputs(this);
       } else {
         this.trySigningIn();
       }
     };

     this.getAddresses = async () => {
       if (!isApp) return this.getAlias();
       const {
         addresses
       } = await wkSendAndWait('emailHandlerGetAddresses');
       return addresses;
     };

     this.getAlias = async () => {
       const {
         alias
       } = await wkSendAndWait('emailHandlerGetAlias', {
         requiresUserPermission: !isApp,
         shouldConsumeAliasIfProvided: !isApp
       });
       return formatAddress(alias);
     };

     this.refreshAlias = () => wkSend('emailHandlerRefreshAlias');

     this.isDeviceSignedIn = async () => {
       const {
         isAppSignedIn
       } = await wkSendAndWait('emailHandlerCheckAppSignedInStatus');
       return !!isAppSignedIn;
     };

     this.storeUserData = ({
       addUserData: {
         token,
         userName
       }
     }) => wkSend('emailHandlerStoreToken', {
       token,
       username: userName
     });

     this.attachTooltip = createAttachTooltip(this.getAlias, this.refreshAlias);
   }

 }

 const DeviceInterface = (() => {
   if (isDDGApp) {
     return isAndroid ? new AndroidInterface() : new AppleDeviceInterface();
   }

   return new ExtensionInterface();
 })();

 module.exports = DeviceInterface;

 },{"./DDGAutofill":1,"./appleDeviceUtils/appleDeviceUtils":5,"./autofill-utils":7,"./scanForInputs.js":11}],3:[function(require,module,exports){
 "use strict";

 const FormAnalyzer = require('./FormAnalyzer');

 const {
   addInlineStyles,
   removeInlineStyles,
   isDDGApp,
   isApp,
   setValue,
   isEventWithinDax
 } = require('./autofill-utils');

 const {
   daxBase64
 } = require('./logo-svg'); // In Firefox web_accessible_resources could leak a unique user identifier, so we avoid it here


 const isFirefox = navigator.userAgent.includes('Firefox');
 const getDaxImg = isDDGApp || isFirefox ? daxBase64 : chrome.runtime.getURL('img/logo-small.svg');

 const getDaxStyles = input => ({
   // Height must be > 0 to account for fields initially hidden
   'background-size': "auto ".concat(input.offsetHeight <= 30 && input.offsetHeight > 0 ? '100%' : '26px'),
   'background-position': 'center right',
   'background-repeat': 'no-repeat',
   'background-origin': 'content-box',
   'background-image': "url(".concat(getDaxImg, ")")
 });

 const INLINE_AUTOFILLED_STYLES = {
   'background-color': '#F8F498',
   'color': '#333333'
 };

 class Form {
   constructor(form, input, attachTooltip) {
     this.form = form;
     this.formAnalyzer = new FormAnalyzer(form, input);
     this.attachTooltip = attachTooltip;
     this.relevantInputs = new Set();
     this.touched = new Set();
     this.listeners = new Set();
     this.addInput(input);
     this.tooltip = null;
     this.activeInput = null;
     this.intObs = new IntersectionObserver(entries => {
       for (const entry of entries) {
         if (!entry.isIntersecting) this.removeTooltip();
       }
     });

     this.removeTooltip = e => {
       if (e && e.target === this.tooltip.host) {
         return;
       }

       this.tooltip.remove();
       this.tooltip = null;
       this.intObs.disconnect();
       window.removeEventListener('mousedown', this.removeTooltip, {
         capture: true
       });
     };

     this.removeInputHighlight = input => {
       removeInlineStyles(input, INLINE_AUTOFILLED_STYLES);
       input.classList.remove('ddg-autofilled');
     };

     this.removeAllHighlights = e => {
       // This ensures we are not removing the highlight ourselves when autofilling more than once
       if (e && !e.isTrusted) return;
       this.execOnInputs(this.removeInputHighlight);
     };

     this.removeInputDecoration = input => {
       removeInlineStyles(input, getDaxStyles(input));
       input.removeAttribute('data-ddg-autofill');
     };

     this.removeAllDecorations = () => {
       this.execOnInputs(this.removeInputDecoration);
       this.listeners.forEach(({
         el,
         type,
         fn
       }) => el.removeEventListener(type, fn));
     };

     this.resetAllInputs = () => {
       this.execOnInputs(input => {
         setValue(input, '');
         this.removeInputHighlight(input);
       });
       if (this.activeInput) this.activeInput.focus();
     };

     this.dismissTooltip = () => {
       this.removeTooltip();
     };

     return this;
   }

   execOnInputs(fn) {
     this.relevantInputs.forEach(fn);
   }

   addInput(input) {
     this.relevantInputs.add(input);
     if (this.formAnalyzer.autofillSignal > 0) this.decorateInput(input);
     return this;
   }

   areAllInputsEmpty() {
     let allEmpty = true;
     this.execOnInputs(input => {
       if (input.value) allEmpty = false;
     });
     return allEmpty;
   }

   addListener(el, type, fn) {
     el.addEventListener(type, fn);
     this.listeners.add({
       el,
       type,
       fn
     });
   }

   decorateInput(input) {
     input.setAttribute('data-ddg-autofill', 'true');
     addInlineStyles(input, getDaxStyles(input));
     this.addListener(input, 'mousemove', e => {
       if (isEventWithinDax(e, e.target)) {
         e.target.style.setProperty('cursor', 'pointer', 'important');
       } else {
         e.target.style.removeProperty('cursor');
       }
     });
     this.addListener(input, 'mousedown', e => {
       if (!e.isTrusted) return;
       if (e.button !== 0) return;

       if (this.shouldOpenTooltip(e, e.target)) {
         if (isEventWithinDax(e, e.target) || isDDGApp && !isApp) {
           e.preventDefault();
           e.stopImmediatePropagation();
         }

         this.touched.add(e.target);
         this.attachTooltip(this, e.target);
       }
     });
     return this;
   }

   shouldOpenTooltip(e, input) {
     return !this.touched.has(input) && this.areAllInputsEmpty() || isEventWithinDax(e, input);
   }

   autofill(alias) {
     this.execOnInputs(input => {
       setValue(input, alias);
       input.classList.add('ddg-autofilled');
       addInlineStyles(input, INLINE_AUTOFILLED_STYLES); // If the user changes the alias, remove the decoration

       input.addEventListener('input', this.removeAllHighlights, {
         once: true
       });
     });

     if (this.tooltip) {
       this.removeTooltip();
     }
   }

 }

 module.exports = Form;

 },{"./FormAnalyzer":4,"./autofill-utils":7,"./logo-svg":9}],4:[function(require,module,exports){
 "use strict";

 class FormAnalyzer {
   constructor(form, input) {
     this.form = form;
     this.autofillSignal = 0;
     this.signals = []; // Avoid autofill on our signup page

     if (window.location.href.match(/^https:\/\/.+\.duckduckgo\.com\/email\/signup/i)) return this;
     this.evaluateElAttributes(input, 3, true);
     form ? this.evaluateForm() : this.evaluatePage();
     return this;
   }

   increaseSignalBy(strength, signal) {
     this.autofillSignal += strength;
     this.signals.push("".concat(signal, ": +").concat(strength));
     return this;
   }

   decreaseSignalBy(strength, signal) {
     this.autofillSignal -= strength;
     this.signals.push("".concat(signal, ": -").concat(strength));
     return this;
   }

   updateSignal({
     string,
     // The string to check
     strength,
     // Strength of the signal
     signalType = 'generic',
     // For debugging purposes, we give a name to the signal
     shouldFlip = false,
     // Flips the signals, i.e. when a link points outside. See below
     shouldCheckUnifiedForm = false,
     // Should check for login/signup forms
     shouldBeConservative = false // Should use the conservative signup regex

   }) {
     const negativeRegex = new RegExp(/sign(ing)?.?in(?!g)|log.?in/i);
     const positiveRegex = new RegExp(/sign(ing)?.?up|join|regist(er|ration)|newsletter|subscri(be|ption)|contact|create|start|settings|preferences|profile|update|checkout|guest|purchase|buy|order|schedule|estimate/i);
     const conservativePositiveRegex = new RegExp(/sign.?up|join|register|newsletter|subscri(be|ption)|settings|preferences|profile|update/i);
     const strictPositiveRegex = new RegExp(/sign.?up|join|register|settings|preferences|profile|update/i);
     const matchesNegative = string.match(negativeRegex); // Check explicitly for unified login/signup forms. They should always be negative, so we increase signal

     if (shouldCheckUnifiedForm && matchesNegative && string.match(strictPositiveRegex)) {
       this.decreaseSignalBy(strength + 2, "Unified detected ".concat(signalType));
       return this;
     }

     const matchesPositive = string.match(shouldBeConservative ? conservativePositiveRegex : positiveRegex); // In some cases a login match means the login is somewhere else, i.e. when a link points outside

     if (shouldFlip) {
       if (matchesNegative) this.increaseSignalBy(strength, signalType);
       if (matchesPositive) this.decreaseSignalBy(strength, signalType);
     } else {
       if (matchesNegative) this.decreaseSignalBy(strength, signalType);
       if (matchesPositive) this.increaseSignalBy(strength, signalType);
     }

     return this;
   }

   evaluateElAttributes(el, signalStrength = 3, isInput = false) {
     Array.from(el.attributes).forEach(attr => {
       if (attr.name === 'style') return;
       const attributeString = "".concat(attr.name, "=").concat(attr.value);
       this.updateSignal({
         string: attributeString,
         strength: signalStrength,
         signalType: "".concat(el.name, " attr: ").concat(attributeString),
         shouldCheckUnifiedForm: isInput
       });
     });
   }

   evaluatePageTitle() {
     const pageTitle = document.title;
     this.updateSignal({
       string: pageTitle,
       strength: 2,
       signalType: "page title: ".concat(pageTitle)
     });
   }

   evaluatePageHeadings() {
     const headings = document.querySelectorAll('h1, h2, h3, [class*="title"], [id*="title"]');

     if (headings) {
       headings.forEach(({
         innerText
       }) => {
         this.updateSignal({
           string: innerText,
           strength: 0.5,
           signalType: "heading: ".concat(innerText),
           shouldCheckUnifiedForm: true,
           shouldBeConservative: true
         });
       });
     }
   }

   evaluatePage() {
     this.evaluatePageTitle();
     this.evaluatePageHeadings(); // Check for submit buttons

     const buttons = document.querySelectorAll("\n                button[type=submit],\n                button:not([type]),\n                [role=button]\n            ");
     buttons.forEach(button => {
       // if the button has a form, it's not related to our input, because our input has no form here
       if (!button.form && !button.closest('form')) {
         this.evaluateElement(button);
         this.evaluateElAttributes(button, 0.5);
       }
     });
   }

   elementIs(el, type) {
     return el.nodeName.toLowerCase() === type.toLowerCase();
   }

   getText(el) {
     // for buttons, we don't care about descendants, just get the whole text as is
     // this is important in order to give proper attribution of the text to the button
     if (this.elementIs(el, 'BUTTON')) return el.innerText;
     if (this.elementIs(el, 'INPUT') && ['submit', 'button'].includes(el.type)) return el.value;
     return Array.from(el.childNodes).reduce((text, child) => this.elementIs(child, '#text') ? text + ' ' + child.textContent : text, '');
   }

   evaluateElement(el) {
     const string = this.getText(el); // check button contents

     if (this.elementIs(el, 'INPUT') && ['submit', 'button'].includes(el.type) || this.elementIs(el, 'BUTTON') && el.type === 'submit' || (el.getAttribute('role') || '').toUpperCase() === 'BUTTON') {
       this.updateSignal({
         string,
         strength: 2,
         signalType: "submit: ".concat(string)
       });
     } // if a link points to relevant urls or contain contents outside the page…


     if (this.elementIs(el, 'A') && el.href && el.href !== '#' || (el.getAttribute('role') || '').toUpperCase() === 'LINK') {
       // …and matches one of the regexes, we assume the match is not pertinent to the current form
       this.updateSignal({
         string,
         strength: 1,
         signalType: "external link: ".concat(string),
         shouldFlip: true
       });
     } else {
       // any other case
       this.updateSignal({
         string,
         strength: 1,
         signalType: "generic: ".concat(string),
         shouldCheckUnifiedForm: true
       });
     }
   }

   evaluateForm() {
     // Check page title
     this.evaluatePageTitle(); // Check form attributes

     this.evaluateElAttributes(this.form); // Check form contents (skip select and option because they contain too much noise)

     this.form.querySelectorAll('*:not(select):not(option)').forEach(el => this.evaluateElement(el)); // If we can't decide at this point, try reading page headings

     if (this.autofillSignal === 0) {
       this.evaluatePageHeadings();
     }

     return this;
   }

 }

 module.exports = FormAnalyzer;

 },{}],5:[function(require,module,exports){
 "use strict";

 // Do not remove -- Apple devices change this when they support modern webkit messaging
 let hasModernWebkitAPI = false; // INJECT hasModernWebkitAPI HERE
 // The native layer will inject a randomised secret here and use it to verify the origin

 let secret = 'PLACEHOLDER_SECRET';

 const ddgGlobals = require('./captureDdgGlobals');
 /**
  * Sends message to the webkit layer (fire and forget)
  * @param {String} handler
  * @param {*} data
  * @returns {*}
  */


 const wkSend = (handler, data = {}) => window.webkit.messageHandlers[handler].postMessage({ ...data,
   messageHandling: { ...data.messageHandling,
     secret
   }
 });
 /**
  * Generate a random method name and adds it to the global scope
  * The native layer will use this method to send the response
  * @param {String} randomMethodName
  * @param {Function} callback
  */


 const generateRandomMethod = (randomMethodName, callback) => {
   ddgGlobals.ObjectDefineProperty(ddgGlobals.window, randomMethodName, {
     enumerable: false,
     // configurable, To allow for deletion later
     configurable: true,
     writable: false,
     value: (...args) => {
       callback(...args);
       delete ddgGlobals.window[randomMethodName];
     }
   });
 };
 /**
  * Sends message to the webkit layer and waits for the specified response
  * @param {String} handler
  * @param {*} data
  * @returns {Promise<*>}
  */


 const wkSendAndWait = async (handler, data = {}) => {
   if (hasModernWebkitAPI) {
     const response = await wkSend(handler, data);
     return ddgGlobals.JSONparse(response);
   }

   try {
     const randMethodName = createRandMethodName();
     const key = await createRandKey();
     const iv = createRandIv();
     const {
       ciphertext,
       tag
     } = await new ddgGlobals.Promise(resolve => {
       generateRandomMethod(randMethodName, resolve);
       data.messageHandling = {
         methodName: randMethodName,
         secret,
         key: ddgGlobals.Arrayfrom(key),
         iv: ddgGlobals.Arrayfrom(iv)
       };
       wkSend(handler, data);
     });
     const cipher = new ddgGlobals.Uint8Array([...ciphertext, ...tag]);
     const decrypted = await decrypt(cipher, key, iv);
     return ddgGlobals.JSONparse(decrypted);
   } catch (e) {
     console.error('decryption failed', e);
     return {
       error: e
     };
   }
 };

 const randomString = () => '' + ddgGlobals.getRandomValues(new ddgGlobals.Uint32Array(1))[0];

 const createRandMethodName = () => '_' + randomString();

 const algoObj = {
   name: 'AES-GCM',
   length: 256
 };

 const createRandKey = async () => {
   const key = await ddgGlobals.generateKey(algoObj, true, ['encrypt', 'decrypt']);
   const exportedKey = await ddgGlobals.exportKey('raw', key);
   return new ddgGlobals.Uint8Array(exportedKey);
 };

 const createRandIv = () => ddgGlobals.getRandomValues(new ddgGlobals.Uint8Array(12));

 const decrypt = async (ciphertext, key, iv) => {
   const cryptoKey = await ddgGlobals.importKey('raw', key, 'AES-GCM', false, ['decrypt']);
   const algo = {
     name: 'AES-GCM',
     iv
   };
   let decrypted = await ddgGlobals.decrypt(algo, cryptoKey, ciphertext);
   let dec = new ddgGlobals.TextDecoder();
   return dec.decode(decrypted);
 };

 module.exports = {
   wkSend,
   wkSendAndWait
 };

 },{"./captureDdgGlobals":6}],6:[function(require,module,exports){
 "use strict";

 // Capture the globals we need on page start
 const secretGlobals = {
   window,
   // Methods must be bound to their interface, otherwise they throw Illegal invocation
   encrypt: window.crypto.subtle.encrypt.bind(window.crypto.subtle),
   decrypt: window.crypto.subtle.decrypt.bind(window.crypto.subtle),
   generateKey: window.crypto.subtle.generateKey.bind(window.crypto.subtle),
   exportKey: window.crypto.subtle.exportKey.bind(window.crypto.subtle),
   importKey: window.crypto.subtle.importKey.bind(window.crypto.subtle),
   getRandomValues: window.crypto.getRandomValues.bind(window.crypto),
   TextEncoder,
   TextDecoder,
   Uint8Array,
   Uint16Array,
   Uint32Array,
   JSONstringify: window.JSON.stringify,
   JSONparse: window.JSON.parse,
   Arrayfrom: window.Array.from,
   Promise: window.Promise,
   ObjectDefineProperty: window.Object.defineProperty
 };
 module.exports = secretGlobals;

 },{}],7:[function(require,module,exports){
 "use strict";

 let isApp = false; // Do not modify or remove the next line -- the app code will replace it with `isApp = true;`
 // INJECT isApp HERE

 const isDDGApp = /(iPhone|iPad|Android|Mac).*DuckDuckGo\/[0-9]/i.test(window.navigator.userAgent) || isApp;
 const isAndroid = isDDGApp && /Android/i.test(window.navigator.userAgent);
 const DDG_DOMAIN_REGEX = new RegExp(/^https:\/\/(([a-z0-9-_]+?)\.)?duckduckgo\.com/);

 const isDDGDomain = () => window.origin.match(DDG_DOMAIN_REGEX); // Send a message to the web app (only on DDG domains)


 const notifyWebApp = message => {
   if (isDDGDomain()) {
     window.postMessage(message, window.origin);
   }
 };
 /**
  * Sends a message and returns a Promise that resolves with the response
  * @param {{} | Function} msgOrFn - a fn to call or an object to send via postMessage
  * @param {String} expectedResponse - the name of the response
  * @returns {Promise<*>}
  */


 const sendAndWaitForAnswer = (msgOrFn, expectedResponse) => {
   if (typeof msgOrFn === 'function') {
     msgOrFn();
   } else {
     window.postMessage(msgOrFn, window.origin);
   }

   return new Promise(resolve => {
     const handler = e => {
       if (e.origin !== window.origin) return;
       if (!e.data || e.data && !(e.data[expectedResponse] || e.data.type === expectedResponse)) return;
       resolve(e.data);
       window.removeEventListener('message', handler);
     };

     window.addEventListener('message', handler);
   });
 }; // Access the original setter (needed to bypass React's implementation on mobile)


 const originalSet = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set; // This ensures that the value is set properly and dispatches events to simulate a real user action

 const setValue = (el, val) => {
   // Avoid keyboard flashing on Android
   if (!isAndroid) {
     el.focus();
   }

   originalSet.call(el, val);
   const ev = new Event('input', {
     bubbles: true
   });
   el.dispatchEvent(ev);
   el.blur();
 };
 /**
  * Use IntersectionObserver v2 to make sure the element is visible when clicked
  * https://developers.google.com/web/updates/2019/02/intersectionobserver-v2
  */


 const safeExecute = (el, fn) => {
   const intObs = new IntersectionObserver(changes => {
     for (const change of changes) {
       // Feature detection
       if (typeof change.isVisible === 'undefined') {
         // The browser doesn't support Intersection Observer v2, falling back to v1 behavior.
         change.isVisible = true;
       }

       if (change.isIntersecting && change.isVisible) {
         fn();
       }
     }

     intObs.disconnect();
   }, {
     trackVisibility: true,
     delay: 100
   });
   intObs.observe(el);
 };

 const getDaxBoundingBox = input => {
   const {
     right: inputRight,
     top: inputTop,
     height: inputHeight
   } = input.getBoundingClientRect();
   const inputRightPadding = parseInt(getComputedStyle(input).paddingRight);
   const width = 30;
   const height = 30;
   const top = inputTop + (inputHeight - height) / 2;
   const right = inputRight - inputRightPadding;
   const left = right - width;
   const bottom = top + height;
   return {
     bottom,
     height,
     left,
     right,
     top,
     width,
     x: left,
     y: top
   };
 };

 const isEventWithinDax = (e, input) => {
   const {
     left,
     right,
     top,
     bottom
   } = getDaxBoundingBox(input);
   const withinX = e.clientX >= left && e.clientX <= right;
   const withinY = e.clientY >= top && e.clientY <= bottom;
   return withinX && withinY;
 };

 const addInlineStyles = (el, styles) => Object.entries(styles).forEach(([property, val]) => el.style.setProperty(property, val, 'important'));

 const removeInlineStyles = (el, styles) => Object.keys(styles).forEach(property => el.style.removeProperty(property));

 const ADDRESS_DOMAIN = '@duck.com';
 /**
  * Given a username, returns the full email address
  * @param {string} address
  * @returns {string}
  */

 const formatAddress = address => address + ADDRESS_DOMAIN;
 /**
  * Escapes any occurrences of &, ", <, > or / with XML entities.
  * @param {string} str The string to escape.
  * @return {string} The escaped string.
  */


 function escapeXML(str) {
   const replacements = {
     '&': '&amp;',
     '"': '&quot;',
     "'": '&apos;',
     '<': '&lt;',
     '>': '&gt;',
     '/': '&#x2F;'
   };
   return String(str).replace(/[&"'<>/]/g, m => replacements[m]);
 }

 module.exports = {
   isApp,
   isDDGApp,
   isAndroid,
   DDG_DOMAIN_REGEX,
   isDDGDomain,
   notifyWebApp,
   sendAndWaitForAnswer,
   setValue,
   safeExecute,
   getDaxBoundingBox,
   isEventWithinDax,
   addInlineStyles,
   removeInlineStyles,
   ADDRESS_DOMAIN,
   formatAddress,
   escapeXML
 };

 },{}],8:[function(require,module,exports){
 "use strict";

 (() => {
   const inject = () => {
     // Polyfills/shims
     require('./requestIdleCallback');

     const DeviceInterface = require('./DeviceInterface');

     DeviceInterface.init();
   }; // chrome is only present in desktop browsers


   if (typeof chrome === 'undefined') {
     inject();
   } else {
     // Check if the site is marked to skip autofill
     chrome.runtime.sendMessage({
       registeredTempAutofillContentScript: true
     }, response => {
       var _response$site, _response$site$broken;

       if (response !== null && response !== void 0 && (_response$site = response.site) !== null && _response$site !== void 0 && (_response$site$broken = _response$site.brokenFeatures) !== null && _response$site$broken !== void 0 && _response$site$broken.includes('autofill')) return;
       inject();
     });
   }
 })();

 },{"./DeviceInterface":2,"./requestIdleCallback":10}],9:[function(require,module,exports){
 "use strict";

 const daxBase64 = 'data:image/svg+xml;base64,PHN2ZyBmaWxsPSJub25lIiBoZWlnaHQ9IjI0IiB2aWV3Qm94PSIwIDAgNDQgNDQiIHdpZHRoPSIyNCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB4bWxuczp4bGluaz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94bGluayI+PGxpbmVhckdyYWRpZW50IGlkPSJhIj48c3RvcCBvZmZzZXQ9Ii4wMSIgc3RvcC1jb2xvcj0iIzYxNzZiOSIvPjxzdG9wIG9mZnNldD0iLjY5IiBzdG9wLWNvbG9yPSIjMzk0YTlmIi8+PC9saW5lYXJHcmFkaWVudD48bGluZWFyR3JhZGllbnQgaWQ9ImIiIGdyYWRpZW50VW5pdHM9InVzZXJTcGFjZU9uVXNlIiB4MT0iMTMuOTI5NyIgeDI9IjE3LjA3MiIgeGxpbms6aHJlZj0iI2EiIHkxPSIxNi4zOTgiIHkyPSIxNi4zOTgiLz48bGluZWFyR3JhZGllbnQgaWQ9ImMiIGdyYWRpZW50VW5pdHM9InVzZXJTcGFjZU9uVXNlIiB4MT0iMjMuODExNSIgeDI9IjI2LjY3NTIiIHhsaW5rOmhyZWY9IiNhIiB5MT0iMTQuOTY3OSIgeTI9IjE0Ljk2NzkiLz48bWFzayBpZD0iZCIgaGVpZ2h0PSI0MCIgbWFza1VuaXRzPSJ1c2VyU3BhY2VPblVzZSIgd2lkdGg9IjQwIiB4PSIyIiB5PSIyIj48cGF0aCBjbGlwLXJ1bGU9ImV2ZW5vZGQiIGQ9Im0yMi4wMDAzIDQxLjA2NjljMTAuNTMwMiAwIDE5LjA2NjYtOC41MzY0IDE5LjA2NjYtMTkuMDY2NiAwLTEwLjUzMDMtOC41MzY0LTE5LjA2NjcxLTE5LjA2NjYtMTkuMDY2NzEtMTAuNTMwMyAwLTE5LjA2NjcxIDguNTM2NDEtMTkuMDY2NzEgMTkuMDY2NzEgMCAxMC41MzAyIDguNTM2NDEgMTkuMDY2NiAxOS4wNjY3MSAxOS4wNjY2eiIgZmlsbD0iI2ZmZiIgZmlsbC1ydWxlPSJldmVub2RkIi8+PC9tYXNrPjxwYXRoIGNsaXAtcnVsZT0iZXZlbm9kZCIgZD0ibTIyIDQ0YzEyLjE1MDMgMCAyMi05Ljg0OTcgMjItMjIgMC0xMi4xNTAyNi05Ljg0OTctMjItMjItMjItMTIuMTUwMjYgMC0yMiA5Ljg0OTc0LTIyIDIyIDAgMTIuMTUwMyA5Ljg0OTc0IDIyIDIyIDIyeiIgZmlsbD0iI2RlNTgzMyIgZmlsbC1ydWxlPSJldmVub2RkIi8+PGcgbWFzaz0idXJsKCNkKSI+PHBhdGggY2xpcC1ydWxlPSJldmVub2RkIiBkPSJtMjYuMDgxMyA0MS42Mzg2Yy0uOTIwMy0xLjc4OTMtMS44MDAzLTMuNDM1Ni0yLjM0NjYtNC41MjQ2LTEuNDUyLTIuOTA3Ny0yLjkxMTQtNy4wMDctMi4yNDc3LTkuNjUwNy4xMjEtLjQ4MDMtMS4zNjc3LTE3Ljc4Njk5LTIuNDItMTguMzQ0MzItMS4xNjk3LS42MjMzMy0zLjcxMDctMS40NDQ2Ny01LjAyNy0xLjY2NDY3LS45MTY3LS4xNDY2Ni0xLjEyNTcuMTEtMS41MTA3LjE2ODY3LjM2My4wMzY2NyAyLjA5Ljg4NzMzIDIuNDIzNy45MzUtLjMzMzcuMjI3MzMtMS4zMi0uMDA3MzMtMS45NTA3LjI3MTMzLS4zMTkuMTQ2NjctLjU1NzMuNjg5MzQtLjU1Ljk0NiAxLjc5NjctLjE4MzMzIDQuNjA1NC0uMDAzNjYgNi4yNy43MzMyOS0xLjMyMzYuMTUwNC0zLjMzMy4zMTktNC4xOTgzLjc3MzctMi41MDggMS4zMi0zLjYxNTMgNC40MTEtMi45NTUzIDguMTE0My42NTYzIDMuNjk2IDMuNTY0IDE3LjE3ODQgNC40OTE2IDIxLjY4MS45MjQgNC40OTkgMTEuNTUzNyAzLjU1NjcgMTAuMDE3NC41NjF6IiBmaWxsPSIjZDVkN2Q4IiBmaWxsLXJ1bGU9ImV2ZW5vZGQiLz48cGF0aCBkPSJtMjIuMjg2NSAyNi44NDM5Yy0uNjYgMi42NDM2Ljc5MiA2LjczOTMgMi4yNDc2IDkuNjUwNi40ODkxLjk3MjcgMS4yNDM4IDIuMzkyMSAyLjA1NTggMy45NjM3LTEuODk0LjQ2OTMtNi40ODk1IDEuMTI2NC05LjcxOTEgMC0uOTI0LTQuNDkxNy0zLjgzMTctMTcuOTc3Ny00LjQ5NTMtMjEuNjgxLS42Ni0zLjcwMzMgMC02LjM0NyAyLjUxNTMtNy42NjcuODYxNy0uNDU0NyAyLjA5MzctLjc4NDcgMy40MTM3LS45MzEzLTEuNjY0Ny0uNzQwNy0zLjYzNzQtMS4wMjY3LTUuNDQxNC0uODQzMzYtLjAwNzMtLjc2MjY3IDEuMzM4NC0uNzE4NjcgMS44NDQ0LTEuMDYzMzQtLjMzMzctLjA0NzY2LTEuMTYyNC0uNzk1NjYtMS41MjktLjgzMjMzIDIuMjg4My0uMzkyNDQgNC42NDIzLS4wMjEzOCA2LjY5OSAxLjA1NiAxLjA0ODYuNTYxIDEuNzg5MyAxLjE2MjMzIDIuMjQ3NiAxLjc5MzAzIDEuMTk1NC4yMjczIDIuMjUxNC42NiAyLjk0MDcgMS4zNDkzIDIuMTE5MyAyLjExNTcgNC4wMTEzIDYuOTUyIDMuMjE5MyA5LjczMTMtLjIyMzYuNzctLjczMzMgMS4zMzEtMS4zNzEzIDEuNzk2Ny0xLjIzOTMuOTAyLTEuMDE5My0xLjA0NS00LjEwMy45NzE3LS4zOTk3LjI2MDMtLjM5OTcgMi4yMjU2LS41MjQzIDIuNzA2eiIgZmlsbD0iI2ZmZiIvPjwvZz48ZyBjbGlwLXJ1bGU9ImV2ZW5vZGQiIGZpbGwtcnVsZT0iZXZlbm9kZCI+PHBhdGggZD0ibTE2LjY3MjQgMjAuMzU0Yy43Njc1IDAgMS4zODk2LS42MjIxIDEuMzg5Ni0xLjM4OTZzLS42MjIxLTEuMzg5Ny0xLjM4OTYtMS4zODk3LTEuMzg5Ny42MjIyLTEuMzg5NyAxLjM4OTcuNjIyMiAxLjM4OTYgMS4zODk3IDEuMzg5NnoiIGZpbGw9IiMyZDRmOGUiLz48cGF0aCBkPSJtMTcuMjkyNCAxOC44NjE3Yy4xOTg1IDAgLjM1OTQtLjE2MDguMzU5NC0uMzU5M3MtLjE2MDktLjM1OTMtLjM1OTQtLjM1OTNjLS4xOTg0IDAtLjM1OTMuMTYwOC0uMzU5My4zNTkzcy4xNjA5LjM1OTMuMzU5My4zNTkzeiIgZmlsbD0iI2ZmZiIvPjxwYXRoIGQ9Im0yNS45NTY4IDE5LjMzMTFjLjY1ODEgMCAxLjE5MTctLjUzMzUgMS4xOTE3LTEuMTkxNyAwLS42NTgxLS41MzM2LTEuMTkxNi0xLjE5MTctMS4xOTE2cy0xLjE5MTcuNTMzNS0xLjE5MTcgMS4xOTE2YzAgLjY1ODIuNTMzNiAxLjE5MTcgMS4xOTE3IDEuMTkxN3oiIGZpbGw9IiMyZDRmOGUiLz48cGF0aCBkPSJtMjYuNDg4MiAxOC4wNTExYy4xNzAxIDAgLjMwOC0uMTM3OS4zMDgtLjMwOHMtLjEzNzktLjMwOC0uMzA4LS4zMDgtLjMwOC4xMzc5LS4zMDguMzA4LjEzNzkuMzA4LjMwOC4zMDh6IiBmaWxsPSIjZmZmIi8+PHBhdGggZD0ibTE3LjA3MiAxNC45NDJzLTEuMDQ4Ni0uNDc2Ni0yLjA2NDMuMTY1Yy0xLjAxNTcuNjM4LS45NzkgMS4yOTA3LS45NzkgMS4yOTA3cy0uNTM5LTEuMjAyNy44OTgzLTEuNzkzYzEuNDQxLS41ODY3IDIuMTQ1LjMzNzMgMi4xNDUuMzM3M3oiIGZpbGw9InVybCgjYikiLz48cGF0aCBkPSJtMjYuNjc1MiAxNC44NDY3cy0uNzUxNy0uNDI5LTEuMzM4My0uNDIxN2MtMS4xOTkuMDE0Ny0xLjUyNTQuNTQyNy0xLjUyNTQuNTQyN3MuMjAxNy0xLjI2MTQgMS43MzQ0LTEuMDA4NGMuNDk5Ny4wOTE0LjkyMjMuNDIzNCAxLjEyOTMuODg3NHoiIGZpbGw9InVybCgjYykiLz48cGF0aCBkPSJtMjAuOTI1OCAyNC4zMjFjLjEzOTMtLjg0MzMgMi4zMS0yLjQzMSAzLjg1LTIuNTMgMS41NC0uMDk1MyAyLjAxNjctLjA3MzMgMy4zLS4zODEzIDEuMjg3LS4zMDQzIDQuNTk4LTEuMTI5MyA1LjUxMS0xLjU1NDcuOTE2Ny0uNDIxNiA0LjgwMzMuMjA5IDIuMDY0MyAxLjczOC0xLjE4NDMuNjYzNy00LjM3OCAxLjg4MS02LjY2MjMgMi41NjMtMi4yODA3LjY4Mi0zLjY2My0uNjUyNi00LjQyMi40Njk0LS42MDEzLjg5MS0uMTIxIDIuMTEyIDIuNjAzMyAyLjM2NSAzLjY4MTQuMzQxIDcuMjA4Ny0xLjY1NzQgNy41OTc0LS41OTQuMzg4NiAxLjA2MzMtMy4xNjA3IDIuMzgzMy01LjMyNCAyLjQyNzMtMi4xNjM0LjA0MDMtNi41MTk0LTEuNDMtNy4xNzItMS44ODQ3LS42NTY0LS40NTEtMS41MjU0LTEuNTE0My0xLjM0NTctMi42MTh6IiBmaWxsPSIjZmRkMjBhIi8+PHBhdGggZD0ibTI4Ljg4MjUgMzEuODM4NmMtLjc3NzMtLjE3MjQtNC4zMTIgMi41MDA2LTQuMzEyIDIuNTAwNmguMDAzN2wtLjE2NSAyLjA1MzRzNC4wNDA2IDEuNjUzNiA0LjczIDEuMzk3Yy42ODkzLS4yNjQuNTE3LTUuNzc1LS4yNTY3LTUuOTUxem0tMTEuNTQ2MyAxLjAzNGMuMDg0My0xLjExODQgNS4yNTQzIDEuNjQyNiA1LjI1NDMgMS42NDI2bC4wMDM3LS4wMDM2LjI1NjYgMi4xNTZzLTQuMzA4MyAyLjU4MTMtNC45MTMzIDIuMjM2NmMtLjYwMTMtLjM0NDYtLjY4OTMtNC45MDk2LS42MDEzLTYuMDMxNnoiIGZpbGw9IiM2NWJjNDYiLz48cGF0aCBkPSJtMjEuMzQgMzQuODA0OWMwIDEuODA3Ny0uMjYwNCAyLjU4NS41MTMzIDIuNzU3NC43NzczLjE3MjMgMi4yNDAzIDAgMi43NjEtLjM0NDcuNTEzMy0uMzQ0Ny4wODQzLTIuNjY5My0uMDg4LTMuMTAycy0zLjE5LS4wODgtMy4xOS42ODkzeiIgZmlsbD0iIzQzYTI0NCIvPjxwYXRoIGQ9Im0yMS42NzAxIDM0LjQwNTFjMCAxLjgwNzYtLjI2MDQgMi41ODEzLjUxMzMgMi43NTM2Ljc3MzcuMTc2IDIuMjM2NyAwIDIuNzU3My0uMzQ0Ni41MTctLjM0NDcuMDg4LTIuNjY5NC0uMDg0My0zLjEwMi0uMTcyMy0uNDMyNy0zLjE5LS4wODQ0LTMuMTkuNjg5M3oiIGZpbGw9IiM2NWJjNDYiLz48cGF0aCBkPSJtMjIuMDAwMiA0MC40NDgxYzEwLjE4ODUgMCAxOC40NDc5LTguMjU5NCAxOC40NDc5LTE4LjQ0NzlzLTguMjU5NC0xOC40NDc5NS0xOC40NDc5LTE4LjQ0Nzk1LTE4LjQ0Nzk1IDguMjU5NDUtMTguNDQ3OTUgMTguNDQ3OTUgOC4yNTk0NSAxOC40NDc5IDE4LjQ0Nzk1IDE4LjQ0Nzl6bTAgMS43MTg3YzExLjEzNzcgMCAyMC4xNjY2LTkuMDI4OSAyMC4xNjY2LTIwLjE2NjYgMC0xMS4xMzc4LTkuMDI4OS0yMC4xNjY3LTIwLjE2NjYtMjAuMTY2Ny0xMS4xMzc4IDAtMjAuMTY2NyA5LjAyODktMjAuMTY2NyAyMC4xNjY3IDAgMTEuMTM3NyA5LjAyODkgMjAuMTY2NiAyMC4xNjY3IDIwLjE2NjZ6IiBmaWxsPSIjZmZmIi8+PC9nPjwvc3ZnPg==';
 module.exports = {
   daxBase64
 };

 },{}],10:[function(require,module,exports){
 "use strict";

 /*!
  * Copyright 2015 Google Inc. All rights reserved.
  *
  * Licensed under the Apache License, Version 2.0 (the "License");
  * you may not use this file except in compliance with the License.
  * You may obtain a copy of the License at
  *
  * http://www.apache.org/licenses/LICENSE-2.0
  *
  * Unless required by applicable law or agreed to in writing, software
  * distributed under the License is distributed on an "AS IS" BASIS,
  * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
  * or implied. See the License for the specific language governing
  * permissions and limitations under the License.
  */

 /*
  * @see https://developers.google.com/web/updates/2015/08/using-requestidlecallback
  */
 window.requestIdleCallback = window.requestIdleCallback || function (cb) {
   return setTimeout(function () {
     const start = Date.now(); // eslint-disable-next-line standard/no-callback-literal

     cb({
       didTimeout: false,
       timeRemaining: function () {
         return Math.max(0, 50 - (Date.now() - start));
       }
     });
   }, 1);
 };

 window.cancelIdleCallback = window.cancelIdleCallback || function (id) {
   clearTimeout(id);
 };

 },{}],11:[function(require,module,exports){
 "use strict";

 const Form = require('./Form');

 const {
   notifyWebApp
 } = require('./autofill-utils'); // Accepts the DeviceInterface as an explicit dependency


 const scanForInputs = DeviceInterface => {
   const forms = new Map();
   const EMAIL_SELECTOR = "\n            input:not([type])[name*=mail i]:not([readonly]):not([disabled]):not([hidden]):not([aria-hidden=true]),\n            input[type=\"\"][name*=mail i]:not([readonly]):not([disabled]):not([hidden]):not([aria-hidden=true]),\n            input[type=text][name*=mail i]:not([readonly]):not([disabled]):not([hidden]):not([aria-hidden=true]),\n            input:not([type])[id*=mail i]:not([readonly]):not([disabled]):not([hidden]):not([aria-hidden=true]),\n            input:not([type])[placeholder*=mail i]:not([readonly]):not([disabled]):not([hidden]):not([aria-hidden=true]),\n            input[type=\"\"][id*=mail i]:not([readonly]):not([disabled]):not([hidden]):not([aria-hidden=true]),\n            input[type=text][placeholder*=mail i]:not([readonly]):not([disabled]):not([hidden]):not([aria-hidden=true]),\n            input[type=\"\"][placeholder*=mail i]:not([readonly]):not([disabled]):not([hidden]):not([aria-hidden=true]),\n            input:not([type])[placeholder*=mail i]:not([readonly]):not([disabled]):not([hidden]):not([aria-hidden=true]),\n            input[type=email]:not([readonly]):not([disabled]):not([hidden]):not([aria-hidden=true]),\n            input[type=text][aria-label*=mail i],\n            input:not([type])[aria-label*=mail i],\n            input[type=text][placeholder*=mail i]:not([readonly])\n        ";

   const addInput = input => {
     const parentForm = input.form;

     if (forms.has(parentForm)) {
       // If we've already met the form, add the input
       forms.get(parentForm).addInput(input);
     } else {
       forms.set(parentForm || input, new Form(parentForm, input, DeviceInterface.attachTooltip));
     }
   };

   const findEligibleInput = context => {
     if (context.nodeName === 'INPUT' && context.matches(EMAIL_SELECTOR)) {
       addInput(context);
     } else {
       context.querySelectorAll(EMAIL_SELECTOR).forEach(addInput);
     }
   }; // For all DOM mutations, search for new eligible inputs and update existing inputs positions


   const mutObs = new MutationObserver(mutationList => {
     for (const mutationRecord of mutationList) {
       if (mutationRecord.type === 'childList') {
         // We query only within the context of added/removed nodes
         mutationRecord.addedNodes.forEach(el => {
           if (el.nodeName === 'DDG-AUTOFILL') return;

           if (el instanceof HTMLElement) {
             window.requestIdleCallback(() => {
               findEligibleInput(el);
             });
           }
         });
       }
     }
   });

   const logoutHandler = () => {
     // remove Dax, listeners, and observers
     mutObs.disconnect();
     forms.forEach(form => {
       form.resetAllInputs();
       form.removeAllDecorations();
     });
     forms.clear();
     notifyWebApp({
       deviceSignedIn: {
         value: false
       }
     });
   };

   DeviceInterface.addLogoutListener(logoutHandler);
   window.requestIdleCallback(() => {
     findEligibleInput(document);
     mutObs.observe(document.body, {
       childList: true,
       subtree: true
     });
   });
 };

 module.exports = scanForInputs;

 },{"./Form":3,"./autofill-utils":7}],12:[function(require,module,exports){
 "use strict";

 module.exports = "\n.wrapper *, .wrapper *::before, .wrapper *::after {\n    box-sizing: border-box;\n}\n.wrapper {\n    position: fixed;\n    top: 0;\n    left: 0;\n    padding: 0;\n    font-family: 'DDG_ProximaNova', 'Proxima Nova', -apple-system,\n    BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen', 'Ubuntu',\n    'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue', sans-serif;\n    -webkit-font-smoothing: antialiased;\n    /* move it offscreen to avoid flashing */\n    transform: translate(-1000px);\n    z-index: 2147483647;\n}\n.tooltip {\n    position: absolute;\n    top: calc(100% + 6px);\n    right: calc(100% - 46px);\n    width: 300px;\n    max-width: calc(100vw - 25px);\n    padding: 8px;\n    border: 1px solid #D0D0D0;\n    border-radius: 10px;\n    background-color: #FFFFFF;\n    font-size: 14px;\n    color: #333333;\n    line-height: 1.3;\n    box-shadow: 0 10px 20px rgba(0, 0, 0, 0.15);\n    z-index: 2147483647;\n}\n.tooltip::before,\n.tooltip::after {\n    content: \"\";\n    width: 0;\n    height: 0;\n    border-left: 10px solid transparent;\n    border-right: 10px solid transparent;\n    display: block;\n    border-bottom: 8px solid #D0D0D0;\n    position: absolute;\n    right: 20px;\n}\n.tooltip::before {\n    border-bottom-color: #D0D0D0;\n    top: -9px;\n}\n.tooltip::after {\n    border-bottom-color: #FFFFFF;\n    top: -8px;\n}\n.tooltip__button {\n    display: flex;\n    flex-direction: column;\n    justify-content: center;\n    align-items: flex-start;\n    width: 100%;\n    padding: 4px 8px 7px;\n    font-family: inherit;\n    font-size: 14px;\n    background: transparent;\n    border: none;\n    border-radius: 6px;\n}\n.tooltip__button:hover {\n    background-color: #3969EF;\n    color: #FFFFFF;\n}\n.tooltip__button__primary-text {\n    font-weight: bold;\n}\n.tooltip__button__secondary-text {\n    font-size: 12px;\n}\n";

 },{}]},{},[8]);
