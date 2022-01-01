import * as WebAuthnJSON from "@github/webauthn-json"

window.addEventListener('load', (event) => {

  let registerKeyForm = document.getElementById("new_user_security_key");
  let authKeyForm = document.getElementById("securityGatewayAuthForm");
  let requestData = document.getElementById("requestData");
  let challengeData = document.getElementById("publicKeyCredential");

  if (registerKeyForm) {
    let labelField = document.getElementById("user_security_key_label");
    registerKeyForm.addEventListener("submit", function (e) {
      e.preventDefault();
      if (labelField.value === "") {
        labelField.parentElement.classList.add("has-error");
      } else {
        labelField.parentElement.classList.remove("has-error");
        if (challengeData.value === "") {
          WebAuthnJSON.create({ "publicKey": JSON.parse(requestData.value) }).then(function(credential) {
            challengeData.value = JSON.stringify(credential);
            registerKeyForm.submit();
          }).catch(function(error) {
            console.log(error);
          });
        }
      }
    }, false);
  }

  if (authKeyForm) {
    if (challengeData) {
      authKeyForm.addEventListener("submit", function (e) {
        e.preventDefault();
        if (challengeData.value === "") {
          WebAuthnJSON.get({ "publicKey": JSON.parse(requestData.value) }).then(function(credential) {
            challengeData.value = JSON.stringify(credential);
            authKeyForm.submit();
          }).catch(function(error) {
            console.log(error);
          });
        }
      }, false);
    }
  }
});
