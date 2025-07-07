import { Token } from "../../generated/schema";

export function createToken(address: string): string {
  let token = Token.load(address);
  if (!token) {
    token = new Token(address);
  }

  token.save();

  return address;
}