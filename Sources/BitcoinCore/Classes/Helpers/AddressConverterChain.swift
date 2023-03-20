import Foundation

public class AddressConverterChain: IAddressConverter {
    private var concreteConverters = [IAddressConverter]()

    public func prepend(addressConverter: IAddressConverter) {
        concreteConverters.insert(addressConverter, at: 0)
    }

    public init() {}

    public func convert(address: String) throws -> Address {
        var errors = [Error]()

        for converter in concreteConverters {
            do {
                let converted = try converter.convert(address: address)
                return converted
            } catch {
                errors.append(error)
            }
        }

        throw BitcoinCoreErrors.AddressConversionErrors(errors: errors)
    }

    public func convert(lockingScriptPayload: Data, type: ScriptType) throws -> Address {
        var errors = [Error]()

        for converter in concreteConverters {
            do {
                let converted = try converter.convert(lockingScriptPayload: lockingScriptPayload, type: type)
                return converted
            } catch {
                errors.append(error)
            }
        }

        throw BitcoinCoreErrors.AddressConversionErrors(errors: errors)
    }

    public func convert(publicKey: PublicKey, type: ScriptType) throws -> Address {
        var errors = [Error]()

        for converter in concreteConverters {
            do {
                let converted = try converter.convert(publicKey: publicKey, type: type)
                return converted
            } catch {
                errors.append(error)
            }
        }

        throw BitcoinCoreErrors.AddressConversionErrors(errors: errors)
    }

}
