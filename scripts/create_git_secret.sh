# Sostituisci <IL_TUO_USERNAME_GITHUB> e <IL_TUO_TOKEN_APPENA_CREATO>
oc create secret generic github-credentials \
  --from-literal=user=<IL_TUO_USERNAME_GITHUB> \
  --from-literal=password=<IL_TUO_TOKEN_APPENA_CREATO> \
  -n open-cluster-management \
  --type=kubernetes.io/basic-auth