# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Loads one of Plasma Fusion's Python tools (installed scripts without a .py suffix, or a tool with
# a dash in its name) as a module for a fuzzer, with atheris' coverage instrumentation on its
# functions. From the source tree the tool is found relative to this file; in ClusterFuzzLite's
# build (.clusterfuzzlite/build.sh) the fuzzer is a PyInstaller package that ships the tool as data
# at the same path below sys._MEIPASS.
import importlib.machinery, importlib.util, pathlib, sys, types

import atheris


def root():
    """The source tree, or the PyInstaller package's unpacked files."""
    unpacked = getattr(sys, "_MEIPASS", None)
    return pathlib.Path(unpacked) if unpacked else pathlib.Path(__file__).resolve().parent.parent


def load(path, name):
    """The tool at path (relative to the source tree) as a module called name."""
    sys.dont_write_bytecode = True   # no __pycache__ next to the tool in the source tree
    loader = importlib.machinery.SourceFileLoader(name, str(root() / path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    for obj in list(vars(module).values()):
        if getattr(obj, "__module__", None) != name:
            continue
        if isinstance(obj, types.FunctionType):
            atheris.instrument_func(obj)
        elif isinstance(obj, type):
            for member in vars(obj).values():
                if isinstance(member, types.FunctionType):
                    atheris.instrument_func(member)
    return module
