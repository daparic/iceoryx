#!/bin/bash
#

export PATH=$CPPTEST_HOME/bin:$PATH
# bazel clean && rm -rf .cpptest .coverage cpptest_results.clog report/
bazel run @cpptest//:coverage --@cpptest//:target=//iceoryx_hoofs/test:hoofs_moduletests_vector  --@cpptest//:psrc_file=//:cpptestcc-bazel-psrc
bazel-out/k8-fastbuild/bin/iceoryx_hoofs/test/hoofs_moduletests_vector.elf --gtest_output=xml
cpptestcov compute -map .cpptest -clog cpptest_results.clog -out .coverage -coverage LC,DC
cpptestcov index .coverage
cpptestcov report html -code -coverage LC,DC -out report/coverage.html .coverage
