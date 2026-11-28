/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "plugincheck.h"

#include <QCoreApplication>
#include <QDir>
#include <QTextStream>

#include <cstdio>

int main(int argc, char *argv[])
{
    const QCoreApplication app(argc, argv);
    const auto args = app.arguments();
    QTextStream error(stderr);
    if (args.size() != 2 || !QDir::isAbsolutePath(args.at(1))) {
        error << "Usage: plasma-fusion-notifications-check ABSOLUTE_PLUGIN\n";
        return 2;
    }
    const auto failure = checkNotificationPlugin(args.at(1));
    if (!failure.isEmpty()) {
        error << failure << '\n';
        return 1;
    }
    return 0;
}
