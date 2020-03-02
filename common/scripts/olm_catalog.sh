#!/bin/bash

set -e

indent() {
  local INDENT="      "
  local INDENT1S="    -"
  sed -e "s/^/${INDENT}/" \
      -e "1s/^${INDENT}/${INDENT1S} /"
}

listCSV() {
  for index in ${!CSVDIRS[*]}
  do
    indent apiVersion < "$(ls "${CSVDIRS[$index]}"/*version.yaml)"
  done
}

addReqCRDs() {
  echo "required:" | sed 's/^/    /' >> ${DEPLOYDIR}/req_crds.yaml.bak
  for f in ${DEPLOYDIR}/req_crds/*; do ( cat "${f}"; echo) | sed 's/^/    /' >> ${DEPLOYDIR}/req_crds.yaml.bak; done
  sed -i'' -e "/customresourcedefinitions:/r ${DEPLOYDIR}/req_crds.yaml.bak" "${CSVFILE}"
}

unindent(){

  local FILENAME=$1
  local INDENT="    "
  local INDENT1S="- "

  if [[ "$OSTYPE" == "linux-gnu" ]]; then
    sed -i -e "1 s/${INDENT1S}/  /" "${FILENAME}"
    sed -i -e "s/${INDENT}//" "${FILENAME}"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' -e "s/^${INDENT}//" "${FILENAME}"
    sed -i '' -e "s/^${INDENT1S}/  /" "${FILENAME}"
  fi
}

removeNamespacePlaceholder(){
  local FILENAME=$1
  if [[ "$OSTYPE" == "linux-gnu" ]]; then
    sed -e '/namespace: placeholder/d' "${FILENAME}"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' -e '/namespace: placeholder/d' "${FILENAME}"
  fi
  
}

DEPLOYDIR=${DIR:-$(cd "$(dirname "$0")"/../../deploy && pwd)}
export CSV_CHANNEL=alpha
export CSV_VERSION=0.0.1

cp "${DEPLOYDIR}"/operator.yaml "${DEPLOYDIR}"/operator.yaml.bak
if [ "$(uname)" = "Darwin" ]; then
  sed -i "" "s|multicloudhub-operator:latest|${IMAGE}|g" "${DEPLOYDIR}"/operator.yaml
else
  sed -i "s|multicloudhub-operator:latest|${IMAGE}|g" "${DEPLOYDIR}"/operator.yaml
fi

operator-sdk generate csv --csv-channel "${CSV_CHANNEL}" --csv-version "${CSV_VERSION}" >/dev/null 2>&1

cp "${DEPLOYDIR}"/operator.yaml.bak "${DEPLOYDIR}"/operator.yaml
rm -f "${DEPLOYDIR}"/operator.yaml.bak

BUILDDIR=${DIR:-$(cd "$(dirname "$0")"/../../build && pwd)}
OLMOUTPUTDIR="${BUILDDIR}"/_output/olm
mkdir -p "${OLMOUTPUTDIR}"

PKGDIR="${DEPLOYDIR}"/olm-catalog/multicloudhub-operator
CSVDIRS[0]=${DIR:-$(cd "${PKGDIR}"/"${CSV_VERSION}" && pwd)}

CRD=$(grep -v -- "---" "$(ls "${DEPLOYDIR}"/crds/*crd.yaml)" | indent)
PKG=$(indent packageName < "$(ls "${PKGDIR}"/*multicloudhub-operator.package.yaml)")
CSVFILE="${PKGDIR}"/"${CSV_VERSION}"/multicloudhub-operator.v"${CSV_VERSION}".clusterserviceversion.yaml

# remove replaces field
sed -ie '/replaces:/d' "${CSVFILE}"

addReqCRDs
rm -f "${DEPLOYDIR}"/req_crds.yaml.bak
# disable all namespaces supported, see https://github.com/operator-framework/operator-sdk/issues/2173 
index=$(grep -n "type: AllNamespaces" "${CSVFILE}" | cut -d ":" -f 1)
index=$((index - 1))
if [ "$(uname)" = "Darwin" ]; then
  sed -i "" "${index}s/true/false/" "${CSVFILE}"
else
  sed -i "${index}s/true/false/" "${CSVFILE}"
fi

NAME=${NAME:-multicloudhub-operator-registry}
NAMESPACE=${NAMESPACE:-multicloud-system}
DISPLAYNAME=${DISPLAYNAME:-multicloudhub-operator}

cat <<< "$CRD" > "${OLMOUTPUTDIR}"/multicloudhub.crd.yaml
cat <<< "$(listCSV)" > "${OLMOUTPUTDIR}"/multicloudhub.csv.yaml

cat > "${OLMOUTPUTDIR}"/multicloudhub.resources.yaml <<EOF | sed 's/^  *$//'
# This file was autogenerated by 'common/scripts/olm_catalog.sh'
# Do not edit it manually!
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: $NAME
spec:
  configMap: $NAME
  displayName: $DISPLAYNAME
  publisher: Red Hat
  sourceType: configmap
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: $NAME
data:
  customResourceDefinitions: |-
$(cat "${OLMOUTPUTDIR}"/multicloudhub.crd.yaml)
  clusterServiceVersions: |-
$(cat "${OLMOUTPUTDIR}"/multicloudhub.csv.yaml)
  packages: |-
$PKG
EOF

unindent "${OLMOUTPUTDIR}"/multicloudhub.crd.yaml
unindent "${OLMOUTPUTDIR}"/multicloudhub.csv.yaml
removeNamespacePlaceholder "${OLMOUTPUTDIR}"/multicloudhub.csv.yaml

\cp -r "${PKGDIR}" "${OLMOUTPUTDIR}"
rm -rf "${DEPLOYDIR}"/olm-catalog

rm -f ${OLMOUTPUTDIR}/*/*/*.yamle
rm -f ${OLMOUTPUTDIR}/*/*/*.yaml-e 

cp "${DEPLOYDIR}"/role.yaml "${OLMOUTPUTDIR}"
cp "${DEPLOYDIR}"/role_binding.yaml "${OLMOUTPUTDIR}"
cp "${DEPLOYDIR}"/service_account.yaml "${OLMOUTPUTDIR}"
cp "${DEPLOYDIR}"/subscription.yaml "${OLMOUTPUTDIR}"
cp "${DEPLOYDIR}"/operator.yaml "${OLMOUTPUTDIR}"
cp "${DEPLOYDIR}"/crds/*_cr.yaml "${OLMOUTPUTDIR}"
cp "${DEPLOYDIR}"/kustomization.yaml "${OLMOUTPUTDIR}"

echo "Created ${OLMOUTPUTDIR}/multicloudhub-operator"
echo "Created ${OLMOUTPUTDIR}/multicloudhub.resources.yaml"
echo "Created ${OLMOUTPUTDIR}/multicloudhub.crd.yaml"
echo "Created ${OLMOUTPUTDIR}/multicloudhub.csv.yaml"
echo "Created ${OLMOUTPUTDIR}/operator.yaml"
echo "Created ${OLMOUTPUTDIR}/subscription.yaml"
echo "Created ${OLMOUTPUTDIR}/service_account.yaml"
echo "Created ${OLMOUTPUTDIR}/role.yaml"
echo "Created ${OLMOUTPUTDIR}/role_binding.yaml"
echo "Created ${OLMOUTPUTDIR}/kustomization.yaml"
