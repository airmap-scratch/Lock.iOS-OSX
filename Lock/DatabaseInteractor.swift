// DatabaseInteractor.swift
//
// Copyright (c) 2016 Auth0 (http://auth0.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation
import Auth0

struct DatabaseInteractor: DatabaseAuthenticatable, DatabaseUserCreator, Loggable {

    private var user: DatabaseUser

    var identifier: String? { return self.user.identifier }
    var email: String? { return self.user.email }
    var username: String? { return self.user.username }
    var password: String? { return self.user.password }

    var validEmail: Bool { return self.user.validEmail }
    var validUsername: Bool { return self.user.validUsername }
    var validPassword: Bool { return self.user.validPassword }
    var usernameValidator: InputValidator { return self.connection.usernameValidator }
    var passwordValidator: InputValidator { return self.connection.passwordValidator }
    var requiredValidator = NonEmptyValidator()

    let authentication: Authentication
    let connection: DatabaseConnection
    let emailValidator: InputValidator = EmailValidator()
    let onAuthentication: Credentials -> ()
    let options: Options
    let customFields: [String: CustomTextField]

    init(connection: DatabaseConnection, authentication: Authentication, user: DatabaseUser, options: Options, callback: Credentials -> ()) {
        self.authentication = authentication
        self.connection = connection
        self.onAuthentication = callback
        self.user = user
        self.options = options
        var fields: [String: CustomTextField] = [:]
        options.customSignupFields.forEach { fields[$0.name] = $0 }
        self.customFields = fields
    }

    mutating func update(attribute: UserAttribute, value: String?) throws {
        let error: ErrorType?
        switch attribute {
        case .Email:
            error = self.updateEmail(value)
        case .Username:
            error = self.updateUsername(value)
        case .Password(let enforcePolicy):
            error = self.updatePassword(value, enforcingPolicy: enforcePolicy)
        case .EmailOrUsername:
            let emailError = self.updateEmail(value)
            let usernameError = self.updateUsername(value)
            if emailError != nil && usernameError != nil {
                error = emailError
            } else {
                error = nil
            }
        case .Custom(let name):
            let field = self.customFields[name]
            error = field?.validation(value)
            self.user.additionalAttributes[name] = value
            self.user.validAdditionaAttribute(name, valid: error == nil)
        }

        if let error = error { throw error }
    }

    func login(callback: (DatabaseAuthenticatableError?) -> ()) {
        let identifier: String

        if let email = self.email where self.validEmail {
            identifier = email
        } else if let username = self.username where self.validUsername {
            identifier = username
        } else {
            return callback(.NonValidInput)
        }

        guard let password = self.password where self.validPassword else { return callback(.NonValidInput) }

        self.authentication
            .login(
                usernameOrEmail: identifier,
                password: password,
                connection: self.connection.name,
                scope: self.options.scope,
                parameters: self.options.parameters
            )
            .start { self.handleLoginResult($0, callback: callback) }
    }

    func create(callback: (DatabaseUserCreatorError?, DatabaseAuthenticatableError?) -> ()) {
        let databaseName = connection.name

        guard
            let email = self.email where self.validEmail,
            let password = self.password where self.validPassword
            else { return callback(.NonValidInput, nil) }

        guard !connection.requiresUsername || self.validUsername else { return callback(.NonValidInput, nil) }

        let username = connection.requiresUsername ? self.username : nil
        let metadata: [String: AnyObject]? = self.user.additionalAttributes.isEmpty ? nil : self.user.additionalAttributes

        let authentication = self.authentication
        let login = authentication.login(
                usernameOrEmail: email,
                password: password,
                connection: databaseName,
                scope: self.options.scope,
                parameters: self.options.parameters
            )
        authentication
            .createUser(
                email: email,
                username: username,
                password: password,
                connection: databaseName,
                userMetadata: metadata
            )
            .start {
                switch $0 {
                case .Success:
                    login.start { self.handleLoginResult($0, callback: { callback(nil, $0) }) }
                case .Failure(let cause as AuthenticationError) where cause.isPasswordNotStrongEnough:
                    callback(.PasswordTooWeak, nil)
                case .Failure(let cause as AuthenticationError) where cause.isPasswordAlreadyUsed:
                    callback(.PasswordAlreadyUsed, nil)
                case .Failure(let cause as AuthenticationError) where cause.code == "invalid_password" && cause.value("name") == "PasswordDictionaryError":
                    callback(.PasswordTooCommon, nil)
                case .Failure(let cause as AuthenticationError) where cause.code == "invalid_password" && cause.value("name") == "PasswordNoUserInfoError":
                    callback(.PasswordHasUserInfo, nil)
                case .Failure(let cause as AuthenticationError) where cause.code == "invalid_password":
                    callback(.PasswordInvalid, nil)
                case .Failure:
                    callback(.CouldNotCreateUser, nil)
                }
            }
    }

    private mutating func updateEmail(value: String?) -> ErrorType? {
        self.user.email = value?.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
        let error = self.emailValidator.validate(value)
        self.user.validEmail = error == nil
        return error
    }

    private mutating func updateUsername(value: String?) -> ErrorType? {
        self.user.username = value?.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
        let error = self.usernameValidator.validate(value)
        self.user.validUsername = error == nil
        return error
    }

    private mutating func updatePassword(value: String?, enforcingPolicy: Bool) -> ErrorType? {
        self.user.password = value
        let error = enforcingPolicy ? self.passwordValidator.validate(value) : self.requiredValidator.validate(value)
        self.user.validPassword = error == nil
        return error
    }

    private func handleLoginResult(result: Auth0.Result<Credentials>, callback: DatabaseAuthenticatableError? -> ()) {
        switch result {
        case .Failure(let cause as AuthenticationError) where cause.isMultifactorRequired || cause.isMultifactorEnrollRequired:
            self.logger.error("Multifactor is required for user <\(self.identifier)>")
            callback(.MultifactorRequired)
        case .Failure(let cause as AuthenticationError) where cause.isTooManyAttempts:
            self.logger.error("Blocked user <\(self.identifier)> for too many login attempts")
            callback(.TooManyAttempts)
        case .Failure(let cause as AuthenticationError) where cause.isInvalidCredentials:
            self.logger.error("Invalid credentials of user <\(self.identifier)>")
            callback(.InvalidEmailPassword)
        case .Failure(let cause as AuthenticationError) where cause.isMultifactorCodeInvalid:
            self.logger.error("Multifactor code is invalid for user <\(self.identifier)>")
            callback(.MultifactorInvalid)
        case .Failure(let cause as AuthenticationError) where cause.isRuleError && cause.description.lowercaseString == "user is blocked":
            self.logger.error("Blocked user <\(self.identifier)>")
            callback(.UserBlocked)
        case .Failure(let cause as AuthenticationError) where cause.code == "password_change_required":
            self.logger.error("Change password required for user <\(self.identifier)>")
            callback(.PasswordChangeRequired)
        case .Failure(let cause as AuthenticationError) where cause.code == "password_leaked":
            self.logger.error("The password of user <\(self.identifier)> was leaked")
            callback(.PasswordLeaked)
        case .Failure(let cause):
            self.logger.error("Failed login of user <\(self.identifier)> with error \(cause)")
            callback(.CouldNotLogin)
        case .Success(let credentials):
            self.logger.info("Authenticated user <\(self.identifier)>")
            callback(nil)
            self.onAuthentication(credentials)
        }
    }
}
