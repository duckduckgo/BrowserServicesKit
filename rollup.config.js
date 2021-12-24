const contentBlockingPath = 'Sources/BrowserServicesKit/ContentBlocking/UserScripts/'

export default [
    {
        input: `${contentBlockingPath}contentblockerrules.js`,
        output: [
            {
                file: `${contentBlockingPath}dist/contentblockerrules.js`,
                format: 'iife'
            }
        ]
    },
    {
        input: `${contentBlockingPath}surrogates.js`,
        output: [
            {
                file: `${contentBlockingPath}dist/surrogates.js`,
                format: 'iife'
            }
        ]
    }
]
