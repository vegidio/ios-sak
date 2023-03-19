# iOS Swiss Army Knife

Swift Package where I keep my custom classes, extensions and other files that help me during the development of my iOS projects.

## 🧰 Toolbox

The Swiss Army Knife is currently divided in 3 packages:

### SAKNetwork

* __RestFactory:__ to make HTTP requests and process the responses.
* __GraphqlFactory:__ to make GraphQL requests and process the responses.

### SAKUtil

* __DateDecodingStrategy.iso8601Complete:__ a full decoding implementation of date ISO8601.
* __Duration:__ enum that makes time conversions easier.
* __Inject:__ property wrappers that can used to do setter based dependency injection.

### SAKView

* __Lazy:__ lazily initialize a view, allocation it only when it's needed.

## 🎨 Code Correctness

This project uses [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) to keep the code formatted and [SwiftLint](https://github.com/realm/SwiftLint) to follow best practices. To format and lint the code, run the command below in the project's root folder:

```
$ swiftformat . && swiftlint
```

## 👨🏾‍💻 Author

Vinicius Egidio ([vinicius.io](http://vinicius.io))
