#!/bin/sh -e

NAME="$(basename $0)"
CWD="$(pwd)"
TMP_PATH="/tmp/fluxgui.$$"
RPM_BUILD_PATH="${TMP_PATH}/rpmbuild"
FLUXGUI_VERSION=""

if [ "$(which rpmbuild)" == "" ]; then
	printf "Unable to find rpmbuild, please use yum or zypper to install the package\n" >&2
	exit 1
fi
if [ "$(which curl)" == "" ]; then
	printf "Unable to find curl, please use yum or zypper to install the package\n" >&2
	exit 1
fi

if [ "$(which git)" == "" ]; then
	printf "Unable to find git, please use yum or zypper to install the package\n" >&2
	exit 1
fi

usage() {
	cat << EOF
$NAME: Fluxgui RPM package generator tool

Usage: $NAME [OPTIONS]

        -h          Show help
        -a [...]    Set package architecture
                    (default: x86_64, available: x86_64, i386)

Example:
       $NAME -a i386

EOF
}

fluxgui_clone() {
	local git_url="https://github.com/xflux-gui/fluxgui.git"

	printf "Cloning fluxgui from ${git_url} ... "
	mkdir -p ${RPM_BUILD_PATH}/BUILD
	git clone ${git_url} ${RPM_BUILD_PATH}/BUILD >/dev/null 2>&1
	if [ $? -eq 0 ]; then
		printf "done\n"
	else
		printf "failed\n"
		exit 1
	fi
}

fluxgui_get_version() {
	local app_version=

	app_version="$(sed -n '/.*version =/ s/.*"\([0-9].*\)".*/\1/p' ${RPM_BUILD_PATH}/BUILD/setup.py)"
	FLUXGUI_VERSION=$app_version
}

fluxgui_release() {
	local new_version="$1"
	local old_version=""
	local release=""

	if [ -r "${CWD}/.version" ]; then
		old_version="$(cat ${CWD}/.version)"
	else
		echo "$new_version" > ${CWD}/.version
	fi
	if [ -r "${CWD}/.release" ]; then
		release=$(cat ${CWD}/.release)
	else
		release=0
	fi

	if [ "$new_version" == "$old_version" ]; then
		release=$(($release + 1))
	else
		release=0
	fi

	echo "$release" > ${CWD}/.release

	RPM_REVISION=$release
}

while getopts "ha:" opt; do
	case "$opt" in
		h)
			usage
			exit 0
		;;
		a)
			RPM_ARCH="$OPTARG"
		;;
	esac
done

if [ -z "$RPM_ARCH" ]; then
	RPM_ARCH="x86_64"
fi

case "${RPM_ARCH}" in
	i386)
		PACKAGE_ARCH="-pre"
		_ARCH="${PACKAGE_ARCH}"
	;;
	x86_64)
		PACKAGE_ARCH="64"
		_ARCH="${PACKAGE_ARCH}"
	;;
esac

mkdir -p ${TMP_PATH}
mkdir -p ${RPM_BUILD_PATH}/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} || exit 1

fluxgui_clone

fluxgui_get_version

if [ "${FLUXGUI_VERSION}" == "" ]; then
	printf "Unable to determine version, something went wrong... \n" >&2
	exit 1
fi

fluxgui_release ${FLUXGUI_VERSION}

XFLUX_PACKAGE_URL="https://justgetflux.com/linux/xflux${PACKAGE_ARCH}.tgz"
RPM_PACKAGE_NAME="fluxgui"
RPM_PACKAGE="${RPM_PACKAGE_NAME}-${FLUXGUI_VERSION}-${RPM_REVISION}.${RPM_ARCH}.rpm"

printf "Downloading xflux (xflux${PACKAGE_ARCH}.tgz) ... "
rc=$(curl -skL -X GET "${XFLUX_PACKAGE_URL}" -o "${RPM_BUILD_PATH}/BUILD/xflux${PACKAGE_ARCH}.tgz" -w '%{http_code}')
if [ "$rc" -eq 200 ]; then
	printf "done\n"
else
	printf "failed\n"
	exit 1
fi

( cd ${RPM_BUILD_PATH}/BUILD
  if [ -r "xflux${PACKAGE_ARCH}.tgz" ]; then
	tar -xf xflux${PACKAGE_ARCH}.tgz >/dev/null 2>&1
  else
	printf "Unable to find xflux${PACKAGE_ARCH}.tgz, can't continue\n" >&2
  fi
)

printf "Generating ${RPM_PACKAGE_NAME}.spec ...\n"
cat << EOF > ${RPM_BUILD_PATH}/SPECS/${RPM_PACKAGE_NAME}.spec
%define           _topdir         ${RPM_BUILD_PATH}
Name:             ${RPM_PACKAGE_NAME}
Version:          ${FLUXGUI_VERSION}
Release:          ${RPM_REVISION}
Summary:          f.lux indicator applet is an indicator applet to control xflux
License:          BSD
Vendor:           f.lux
Group:            System/X11/Utilities
URL:              https://justgetflux.com/
BugURL:           https://github.com/xflux-gui/fluxgui/issues
ExcludeArch:      noarch
BuildRequires:    python >= 2.7
Requires:         python-appindicator
Requires:         python-gconf
Requires:         python-xdg
Requires:         python-pexpect
Requires(post):   coreutils shared-mime-info desktop-file-utils
Requires(postun): shared-mime-info desktop-file-utils
Packager:         Robert Milasan <robert@linux-source.org>

%description
f.lux indicator applet is an indicator applet to control xflux, an
application that makes the color of your computer's display adapt to the time
of day, warm at nights and like sunlight during the day

%build

%install
python setup.py install --root=\$RPM_BUILD_ROOT

%post
if test -x /usr/bin/update-mime-database; then
  /usr/bin/update-mime-database "/usr/share/mime" || true
fi
if test -x /usr/bin/update-desktop-database; then
  /usr/bin/update-desktop-database --quiet "/usr/share/applications" || true
fi
if test -x /usr/bin/gtk-update-icon-cache; then
    for icons in elementary-xfce-dark elementary-xfce elementary breeze-dark breeze Adwaita \\
      ubuntu-mono-light ubuntu-mono-dark hicolor; do
      if [ -d "/usr/share/icons/\${icons}" ]; then
         echo "Updating \${icons} icon cache ..."
         /usr/bin/gtk-update-icon-cache --quiet --force "/usr/share/icons/\${icons}" >/dev/null 2>&1 || true
      fi
    done
fi
exit 0

%postun
if [ \$1 -eq 0 ]; then
  if test -x /usr/bin/gtk-update-icon-cache; then
    for icons in elementary-xfce-dark elementary-xfce elementary breeze-dark breeze Adwaita \\
      ubuntu-mono-light ubuntu-mono-dark hicolor; do
      if [ -d "/usr/share/icons/\${icons}" ]; then
         echo "Updating \${icons} icon cache ..."
         /usr/bin/gtk-update-icon-cache --quiet --force "/usr/share/icons/\${icons}" >/dev/null 2>&1 || true
      fi
    done
  fi
fi
if [ \$1 -eq 0 ]; then
  if test -x /usr/bin/update-desktop-database; then
    /usr/bin/update-desktop-database --quiet "/usr/share/applications" || true
  fi
fi
if [ \$1 -eq 0 ]; then
  if test -x /usr/bin/update-mime-database; then
    /usr/bin/update-mime-database "/usr/share/mime" || true
  fi
fi
exit 0

%clean
rm -rfv \$RPM_BUILD_ROOT

%files
%defattr(0644, root, root, 0755)
%attr(755,root,root) /usr/bin/fluxgui
%attr(755,root,root) /usr/bin/xflux
/usr/lib/python*/site-packages/f.lux_indicator_applet-*-py2.*.egg-info
/usr/lib/python*/site-packages/fluxgui
/usr/lib/python*/site-packages/fluxgui/__init__.py
/usr/lib/python*/site-packages/fluxgui/__init__.pyc
/usr/lib/python*/site-packages/fluxgui/exceptions.py
/usr/lib/python*/site-packages/fluxgui/exceptions.pyc
/usr/lib/python*/site-packages/fluxgui/fluxapp.py
/usr/lib/python*/site-packages/fluxgui/fluxapp.pyc
/usr/lib/python*/site-packages/fluxgui/fluxcontroller.py
/usr/lib/python*/site-packages/fluxgui/fluxcontroller.pyc
/usr/lib/python*/site-packages/fluxgui/preferences.glade
/usr/lib/python*/site-packages/fluxgui/settings.py
/usr/lib/python*/site-packages/fluxgui/settings.pyc
/usr/lib/python*/site-packages/fluxgui/xfluxcontroller.py
/usr/lib/python*/site-packages/fluxgui/xfluxcontroller.pyc
/usr/share/applications/fluxgui.desktop
/usr/share/icons/elementary-xfce-dark/panel/22/fluxgui-panel.svg
/usr/share/icons/elementary-xfce/panel/22/fluxgui-panel.svg
/usr/share/icons/elementary/status/24/fluxgui-panel.svg
/usr/share/icons/breeze-dark/status/22/fluxgui-panel.svg
/usr/share/icons/breeze/status/22/fluxgui-panel.svg
/usr/share/icons/Adwaita/16x16/status/fluxgui-panel.svg
/usr/share/icons/ubuntu-mono-light/status/24/fluxgui-panel.svg
/usr/share/icons/ubuntu-mono-light/status/22/fluxgui-panel.svg
/usr/share/icons/ubuntu-mono-light/status/16/fluxgui-panel.svg
/usr/share/icons/ubuntu-mono-dark/status/24/fluxgui-panel.svg
/usr/share/icons/ubuntu-mono-dark/status/22/fluxgui-panel.svg
/usr/share/icons/ubuntu-mono-dark/status/16/fluxgui-panel.svg
/usr/share/icons/hicolor/96x96/apps/fluxgui.svg
/usr/share/icons/hicolor/64x64/apps/fluxgui.svg
/usr/share/icons/hicolor/48x48/apps/fluxgui.svg
/usr/share/icons/hicolor/32x32/apps/fluxgui.svg
/usr/share/icons/hicolor/24x24/apps/fluxgui.svg
/usr/share/icons/hicolor/22x22/apps/fluxgui.svg
/usr/share/icons/hicolor/16x16/apps/fluxgui.svg
EOF

printf "Generating RPM package: ${RPM_PACKAGE}\n"
( cd ${RPM_BUILD_PATH}/SPECS
  rpmbuild -bb --quiet --target=${RPM_ARCH} ${RPM_PACKAGE_NAME}.spec 2>/dev/null
)

if [ -r "${RPM_BUILD_PATH}/RPMS/${RPM_ARCH}/${RPM_PACKAGE}" ]; then
	cp -af ${RPM_BUILD_PATH}/RPMS/${RPM_ARCH}/${RPM_PACKAGE} ${CWD}/${RPM_PACKAGE}
   	printf "Package generated: ${CWD}/${RPM_PACKAGE}\n"
else
	printf "Failed to generate RPM package\n" >&2
	exit 1
fi

rm -fr ${TMP_PATH}
