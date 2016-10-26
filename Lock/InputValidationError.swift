// InputValidationError.swift
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

enum InputValidationError: ErrorType {
    case MustNotBeEmpty
    case NotAnEmailAddress
    case NotAUsername
    case NotAOneTimePassword
    case PasswordPolicyViolation(result: [RuleResult])

    func localizedMessage(withConnection connection: DatabaseConnection) -> String {
        switch self {
        case .NotAUsername:
            let format = "Can only contain between %d to %d alphanumeric characters and \'_\'.".i18n(key: "com.auth0.lock.input.username.error", comment: "invalid username")
            return String(format: format, connection.usernameValidator.min, connection.usernameValidator.max)
        case .NotAnEmailAddress:
            return "Must be a valid email address".i18n(key: "com.auth0.lock.input.email.error", comment: "invalid email")
        case .MustNotBeEmpty:
            return "Must not be empty".i18n(key: "com.auth0.lock.input.empty.error", comment: "empty input")
        case .NotAOneTimePassword:
            return "Must be a valid numeric code".i18n(key: "com.auth0.lock.input.otp.error", comment: "invalid otp")
        case .PasswordPolicyViolation(let result) where result.count < 2:
            return "Must not be empty".i18n(key: "com.auth0.lock.input.empty.error", comment: "empty input")
        case .PasswordPolicyViolation(let result):
            return result.first?.message ?? "Must not be empty".i18n(key: "com.auth0.lock.input.empty.error", comment: "empty input")
        }
    }
}
