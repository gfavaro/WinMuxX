// Copyright (c) 2023 Jeff Lebrun
//
//  Licensed under the MIT License.
//
//  The full text of the license can be found in the file named LICENSE.

#if canImport(Darwin)
	import Darwin.C
#elseif canImport(Glibc)
	import Glibc
#elseif canImport(ucrt)
	import ucrt
#else
	#error("Unsupported Platform")
#endif

import CTOML

public extension TOMLValue {
	internal init(tomlValuePointer: OpaquePointer) {
		self.tomlValuePointer = tomlValuePointer
		self.storage = TOMLNodeStorage(tomlValuePointer)
	}

	internal init(tomlValuePointer: OpaquePointer, storage: TOMLNodeStorage) {
		self.tomlValuePointer = tomlValuePointer
		self.storage = storage
	}

	init(booleanLiteral value: Bool) {
		self.init(tomlValuePointer: nodeFromBool(value))
	}

	init<I: FixedWidthInteger>(_ value: I) {
		self.init(tomlValuePointer: nodeFromInt(Int64(value)))
	}

	init(integerLiteral value: Int) {
		self.init(tomlValuePointer: nodeFromInt(Int64(value)))
	}

	init(_ value: TOMLInt) {
		self.init(tomlValuePointer: nodeFromInt(Int64(value.value)))
		self.tomlInt = value
	}

	init(floatLiteral value: Double) {
		self.init(tomlValuePointer: nodeFromDouble(value))
	}

	init(stringLiteral value: String) {
		self.init(tomlValuePointer: nodeFromString(value))
	}

	init(_ value: TOMLDate) {
		self.init(tomlValuePointer: nodeFromDate(value.cTOMLDate))
	}

	init(_ value: TOMLTime) {
		self.init(tomlValuePointer: nodeFromTime(value.cTOMLTime))
	}

	init(_ value: TOMLDateTime) {
		self.init(tomlValuePointer: value.withCTOMLDateTime { nodeFromDateTime($0) })
	}

	init(_ value: TOMLTable) {
		self.init(tomlValuePointer: nodeFromTable(value.tablePointer), storage: value.storage)
	}

	init(dictionaryLiteral elements: (String, TOMLValue)...) {
		self.init(TOMLTable(Dictionary(uniqueKeysWithValues: elements)))
	}

	init(_ value: TOMLArray) {
		self.init(tomlValuePointer: nodeFromArray(value.arrayPointer), storage: value.storage)
	}

	init(arrayLiteral elements: TOMLValue...) {
		self.init(TOMLArray(elements))
	}
}
