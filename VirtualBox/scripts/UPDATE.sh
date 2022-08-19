#!/bin/bash
#
# Script to install/update the SyneRBI VM. It could also be used for any
# other system but will currently change your .sirfrc.
# This is to be avoided later on.
#
# Warning: if you use a local branch (as opposed to a remote branch or a tag), this
# script will merge remote updates automatically, without asking.
#
# Authors: Kris Thielemans, Evgueni Ovtchinnikov, Edoardo Pasca,
# Casper da Costa-Luis
# Copyright 2016-2022 University College London
# Copyright 2016-2022 Rutherford Appleton Laboratory STFC
#
# This is software developed for the Collaborative Computational
# Project in Synergistic Reconstruction for Biomedical Imaging (formerly PETMR)
# (http://www.ccpsynerbi.ac.uk/).

#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0.txt
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
#=========================================================================

#### first some functions definitions

# print usage (taking script name as first argument)
print_usage(){
  echo "Usage: $1 [-t tag] [-j n] [-s]"
  echo "Use the tag option to checkout a specific version of the SIRF-SuperBuild."
  echo "   Otherwise the most recent release will be used."
  echo "Use the -j option to change the number of parallel builds from the default ${num_parallel}"
  echo "Use the -s option to update and install necessary system and Python components."
  echo "  We recommend to do this once when upgrading between major versions."
}

# SuperBuild software (checkout appropriate version)
install_SuperBuild_source(){
  echo "==================== SuperBuild checkout ====================="
  cd $SIRF_SRC_PATH
  SB_repo=https://github.com/SyneRBI/SIRF-SuperBuild.git
  if [ ! -d SIRF-SuperBuild ] 
  then
    git clone $SB_repo
    cd SIRF-SuperBuild
  else
    cd SIRF-SuperBuild
    git fetch --tags --all
  fi
  # go to SB_TAG
  if [ $1 = 'default' ] 
  then
   # get the latest tag matching v
   #SB_TAG=`git fetch; git for-each-ref refs/tags/v* --sort=-taggerdate --format='%(refname:short)' --count=1`
   SB_TAG=`git tag | xargs -I@ git log --format=format:"%at @%n" -1 @ | sort | awk '{print $2}' | tail -1`
  else
   SB_TAG=$1
  fi
  clone_or_pull $SB_repo $SB_TAG
  cd ..
}

# SuperBuild cmake
SuperBuild_install(){
  echo "==================== SuperBuild cmake/make ====================="
  cd $SIRF_SRC_PATH
  buildVM=buildVM
  mkdir -p $buildVM
  
  cd $buildVM
  cmake ../SIRF-SuperBuild \
        -DCMAKE_INSTALL_PREFIX=${SIRF_INSTALL_PATH} \
        -U\*_URL -U\*_TAG \
        -DUSE_SYSTEM_SWIG=On \
        -DUSE_SYSTEM_Boost=On \
        -DUSE_SYSTEM_Armadillo=On \
        -DUSE_SYSTEM_FFTW3=On \
        -DUSE_SYSTEM_HDF5=ON \
        -DBUILD_siemens_to_ismrmrd=On \
        -DUSE_ITK=ON \
        -DDEVEL_BUILD=OFF\
        -DNIFTYREG_USE_CUDA=OFF\
        -DBUILD_CIL=ON\
        -DPYTHON_EXECUTABLE="$PYTHON_EXECUTABLE"\
        -DBUILD_pet_rd_tools=ON
  cmake --build . -j${num_parallel}

}

# define a function to get the source
# arguments: name_of_repo [git_ref]
clone_or_pull()
{
  repoURL=$1
  repo=`basename $1`
  repo=${repo/.git//}
  git_ref=${2:-master} # default to master
  echo "======================  Getting/updating source for $repo"
  cd $SIRF_SRC_PATH
  if [ -d $repo ]
  then
    cd $repo
    if [ $update_remote == 1 ]; then
        git remote set-url origin $repoURL
    fi
    git fetch --tags --all
  else
    git clone --recursive $repoURL
    cd $repo
  fi
  git checkout $git_ref
  # check if we are not in detached HEAD state
  if git symbolic-ref -q HEAD
  then
      # We are on a local branch.
      echo "Warning: updating your local branch with 'git pull'"
      git pull
  fi
  git submodule update --init
}

# define a function to build and install
# arguments: name_of_repo [cmake arguments]
build_and_install()
{
  repo=$1
  shift
  echo "======================  Building $repo"
  cd $BUILD_PATH
  if [ -d $repo ]
  then
    cd $repo
    cmake .
  else
    mkdir $repo
    cd $repo
    cmake $* $SIRF_SRC_PATH/$repo
  fi
  echo "======================  Installing $repo"
  make -j${num_parallel} install
}

# function to do everything
update()
{
  clone_or_pull $1
  build_and_install $*
}

# end of function definitions
#=========================================================================
# start of script

# Exit if something goes wrong
set -e
# give a sensible error message (note: works only in bash)
trap 'echo An error occurred in $0 at line $LINENO. Current working-dir: $PWD' ERR
SB_TAG='default'
num_parallel=2
update_remote=0
apt_install=0
while getopts hrst:j: option
 do
 case "${option}"
 in
  r) update_remote=1;;
  s) apt_install=1;;
  t) SB_TAG=$OPTARG;;
  j) num_parallel=$OPTARG;;
  h)
   print_usage $0
   exit 
   ;;
  *)
   echo "Wrong option passed. Use the -h option to get some help." >&2
   exit 1
  ;;
 esac
done
# get rid of processed options
shift $((OPTIND-1))

if [ $# -ne 0 ]
then
  echo "Wrong command line format. Use the -h option to get some help." >&2
  exit 1
fi

if [ -r ~/.sirfrc ]
then
  source ~/.sirfrc
else
  if [ ! -e ~/.bashrc ]
  then 
    touch ~/.bashrc
  fi
  #added=`grep -c "source ~/.sirfrc" ~/.bashrc`
  added=`cat ~/.bashrc | gawk 'BEGIN{v=0;} {if ($0 == "source ~/.sirfrc") v=v+1;} END{print v}'`
  if [ $added -eq "0" ] 
  then
    echo "I will create a ~/.sirfrc file and source this from your .bashrc"
    echo "source ~/.sirfrc" >> ~/.bashrc
  else
  echo "source ~/.sirfrc already present $added times in .bashrc. Not adding"
  fi
fi

# check current version (if any) to take into account later on
# (the new VM version will be saved at the end of the script)
if [ -r ~/.sirf_VM_version ]
then
  source ~/.sirf_VM_version
else
  if [ -r /usr/local/bin/update_VM.sh ]
  then
    # we are on the very first VM
    echo '======================================================'
    echo 'You have a very old VM. Aborting'
    echo '======================================================'
    exit 1
  else
    if [ -r ~/.sirfrc ]; then
      SIRF_VM_VERSION=0.9
      echo '======================================================'
      if [ $apt_install == 1 ]; then
        echo 'You have a very old VM. This update might fail.'
        echo 'You probably will have to "rm -rf ~/devel/buildVM" first.'
      else
        echo 'You have a very old VM. You have to run with -s (but the update might fail anyway).'
        exit 1
      fi
      echo '======================================================'
    else
      SIRF_VM_VERSION=new_VM
    fi
  fi
fi

# location of sources
if [ -z $SIRF_SRC_PATH ]
then
  export SIRF_SRC_PATH=~/devel
fi
if [ ! -d $SIRF_SRC_PATH ]
then
  mkdir -p $SIRF_SRC_PATH
fi

# old VM repos
if [ -d $SIRF_SRC_PATH/CCPPETMR_VM ]; then
    echo '======================================================'
    echo "$SIRF_SRC_PATH/CCPPETMR_VM is no longer used. We recommend removing it."
    echo '======================================================'
fi
if [ -d $SIRF_SRC_PATH/SyneRBI_VM ]; then
    echo '======================================================'
    echo "$SIRF_SRC_PATH/SyneRBI_VM is no longer used. We recommend removing it."
    echo '======================================================'
fi

SIRF_INSTALL_PATH=$SIRF_SRC_PATH/install

# Checkout correct version of the SuperBuild
install_SuperBuild_source $SB_TAG

# Optionally install/update pre-requisites
if [ $apt_install == 1 ]; then
  cd "$SIRF_SRC_PATH"/SIRF-SuperBuild/VirtualBox/scripts
  sudo -H ./INSTALL_prerequisites_with_apt-get.sh
  sudo -H ./INSTALL_CMake.sh
fi

# best to use full path for python3
PYTHON_EXECUTABLE=$(which python3)
if which python3; then
  PYTHON_EXECUTABLE=$(which python3)
else
  PYTHON_EXECUTABLE=$(which python)
fi

# Add ~/.local/bin (or whatever it has to be) to the PATH as this is where pip installs executables
PY_USER_BIN=`"$PYTHON_EXECUTABLE" -c 'import site; import os; print ( os.path.join(site.USER_BASE , "bin") )'`
export PATH=${PY_USER_BIN}:${PATH}

# Optionally install/update python packages
if [ $apt_install == 1 ]; then
  ./INSTALL_python_packages.sh --python "$PYTHON_EXECUTABLE"
fi

# ignore notebook keys, https://github.com/CCPPETMR/SIRF-Exercises/issues/20
"$PYTHON_EXECUTABLE" -m pip install -U --user nbstripout
git config --global filter.nbstripout.extrakeys '
  metadata.celltoolbar metadata.language_info.codemirror_mode.version
  metadata.language_info.pygments_lexer metadata.language_info.version'


# Launch the SuperBuild
SuperBuild_install

# copy scripts into the path
cp -vp $SIRF_SRC_PATH/SIRF-SuperBuild/VirtualBox/scripts/update*sh $SIRF_INSTALL_PATH/bin

# Get extra python tools
clone_or_pull  https://github.com/SyneRBI/ismrmrd-python-tools.git
cd $SIRF_SRC_PATH/ismrmrd-python-tools
"$PYTHON_EXECUTABLE" setup.py install --user

# install the SIRF-Exercises
cd $SIRF_SRC_PATH
clone_or_pull  https://github.com/SyneRBI/SIRF-Exercises.git
cd $SIRF_SRC_PATH/SIRF-Exercises
# Python (runtime)
if [ -f requirements.txt ]; then
  "$PYTHON_EXECUTABLE" -m pip install -U -r requirements.txt
fi

nbstripout --install

# check STIR-exercises
cd $SIRF_SRC_PATH
if [ -d STIR-exercises ]; then
  cd STIR-exercises
  git pull
fi

# copy help file to Desktop
if [ ! -d ~/Desktop ]
then
  if [ -e ~/Desktop ]
    then 
	mv ~/Desktop ~/Desktop.file
  fi
  mkdir ~/Desktop 
fi 
cp -vp $SIRF_SRC_PATH/SIRF-SuperBuild/VirtualBox/HELP.txt ~/Desktop/

if [ -r ~/.sirfc ]; then
  echo "Moving existing ~/.sirfc to a backup copy"
  mv -v ~/.sirfc ~/.sirfc.old
fi
echo "export SIRF_SRC_PATH=$SIRF_SRC_PATH" > ~/.sirfrc
echo "source ${SIRF_INSTALL_PATH}/bin/env_sirf.sh" >> ~/.sirfrc
# add local python-bin to PATH
echo "export PATH=${PY_USER_BIN}:\${PATH}" >> ~/.sirfrc
echo "export EDITOR=nano" >> ~/.sirfrc
if [ ! -z "$STIR_exercises_PATH" ]; then
    echo "export STIR_exercises_PATH=$SIRF_SRC_PATH/STIR-exercises" >> ~/.sirfrc
fi

version=`echo -n "export SIRF_VM_VERSION=" | cat - ${SIRF_SRC_PATH}/SIRF-SuperBuild/VirtualBox/VM_version.txt`
echo $version > ~/.sirf_VM_version

echo ""
echo "SIRF update done!"
echo "Contents of your .sirfrc is now as follows"
echo "=================================================="
cat ~/.sirfrc
echo "=================================================="
echo "This file is sourced from your .bashrc."
echo "Close your terminal and re-open a new one to update your environment variables"
