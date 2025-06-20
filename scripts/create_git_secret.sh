oc create secret generic github-credentials \
  --from-literal=user=<USERNAME_GITHUB> \
  --from-literal=accessToken=<YOUR_TOKEN> \
  -n open-cluster-management \
  --type=kubernetes.io/basic-auth