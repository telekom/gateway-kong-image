// SPDX-FileCopyrightText: 2025 Deutsche Telekom AG
//
// SPDX-License-Identifier: Apache-2.0

module.exports = {
    branches: ['main'],
    repositoryUrl: 'git@github.com:telekom/gateway-kong-image.git',
    plugins: [
        '@semantic-release/commit-analyzer',
        'semantic-release-export-data',
        '@semantic-release/release-notes-generator',
        '@semantic-release/changelog',
        '@semantic-release/github',
        [
            '@semantic-release/git',
            {
                assets: ['CHANGELOG.md']
            },
        ],
    ],
};
