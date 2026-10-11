# Rendered by scripts/bootstrap.sh: __REPO_URL__ and __REVISION__ are filled in
# so CI can test the exact commit under review.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-root
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io/background
spec:
  project: default
  source:
    repoURL: __REPO_URL__
    targetRevision: __REVISION__
    path: bootstrap/root
    helm:
      valuesObject:
        repoURL: __REPO_URL__
        revision: __REVISION__
        monitoring:
          enabled: __MONITORING__
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
