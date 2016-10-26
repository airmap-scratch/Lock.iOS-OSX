// Validators.swift
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

protocol InputValidator {
    func validate(value: String?) -> ErrorType?
}

public class OneTimePasswordValidator: InputValidator {
    func validate(value: String?) -> ErrorType? {
        guard let value = value?.trimmed where !value.isEmpty else { return InputValidationError.MustNotBeEmpty }
        guard value.rangeOfCharacterFromSet(NSCharacterSet.decimalDigitCharacterSet()) != nil else { return InputValidationError.NotAOneTimePassword }
        return nil
    }
}

public class NonEmptyValidator: InputValidator {
    func validate(value: String?) -> ErrorType? {
        guard let value = value?.trimmed where !value.isEmpty else { return InputValidationError.MustNotBeEmpty }
        return nil
    }
}

public class UsernameValidator: InputValidator {

    let invalidSet: NSCharacterSet?
    let range: Range<Int>

    var min: Int { return self.range.startIndex }
    var max: Int { return self.range.endIndex - 1 }

    public init() {
        self.range = 1..<Int.max
        self.invalidSet = nil
    }

    public init(withLength range: Range<Int>, characterSet: NSCharacterSet) {
        self.invalidSet = characterSet
        self.range = range
    }

    func validate(value: String?) -> ErrorType? {
        guard let username = value?.trimmed where !username.isEmpty else { return InputValidationError.MustNotBeEmpty }
        guard self.range ~= username.characters.count else { return self.invalidSet == nil ? InputValidationError.MustNotBeEmpty : InputValidationError.NotAUsername }
        guard let characterSet = self.invalidSet else { return nil }
        guard username.rangeOfCharacterFromSet(characterSet) == nil else { return InputValidationError.NotAUsername }
        return nil
    }

    public static var auth0: NSCharacterSet {
        let set = NSMutableCharacterSet()
        set.formUnionWithCharacterSet(NSCharacterSet.alphanumericCharacterSet())
        set.addCharactersInString("_")
        return set.invertedSet
    }
}

public class EmailValidator: InputValidator {
    let predicate: NSPredicate

    public init() {
        let regex = "[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*@(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?"
        self.predicate = NSPredicate(format: "SELF MATCHES %@", regex)
    }

    func validate(value: String?) -> ErrorType? {
        guard let email = value?.trimmed where !email.isEmpty else { return InputValidationError.MustNotBeEmpty }
        guard self.predicate.evaluateWithObject(email) else { return InputValidationError.NotAnEmailAddress }
        return nil
    }
}

public class PasswordPolicyValidator: InputValidator {
    let policy: PasswordPolicy

    init(policy: PasswordPolicy) {
        self.policy = policy
    }

    func validate(value: String?) -> ErrorType? {
        let result = self.policy.on(value)
        let valid = result.reduce(true) { $0 && $1.valid }
        guard !valid else { return nil }
        return InputValidationError.PasswordPolicyViolation(result: result)
    }
}

private extension String {
    var trimmed: String {
        return self.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
    }
}
