import { BCS, getSuiMoveConfig } from '@mysten/bcs';
import { SHA256 } from 'crypto-js';
import { MerkleTree } from 'merkletreejs';

const bcs = new BCS(getSuiMoveConfig());

const ADDRESS_ONE =
  '0x94fbcf49867fd909e6b2ecf2802c4b2bba7c9b2d50a13abbb75dbae0216db82a';

const AMOUNT_ONE = 55;

const ADDRESS_TWO =
  '0xb4536519beaef9d9207af2b5f83ae35d4ac76cc288ab9004b39254b354149d27';

const AMOUNT_TWO = 27;

const DATA_ONE = new Uint8Array([
  ...bcs.ser(BCS.ADDRESS, ADDRESS_ONE).toBytes(),
  ...bcs.ser(BCS.U64, AMOUNT_ONE).toBytes(),
]);

const DATA_TWO = new Uint8Array([
  ...bcs.ser(BCS.ADDRESS, ADDRESS_TWO).toBytes(),
  ...bcs.ser(BCS.U64, AMOUNT_TWO).toBytes(),
]);

const leaves = [DATA_ONE, DATA_TWO].map(x => SHA256(x.toString()));
const tree = new MerkleTree(leaves, SHA256, { sortPairs: true });
const root = tree.getRoot().toString('hex');
const leaf = SHA256(DATA_ONE.toString());
const proof = tree.getProof(leaf.toString());

const wrongLeaf = new Uint8Array([
  ...bcs.ser(BCS.ADDRESS, ADDRESS_ONE).toBytes(),
  ...bcs.ser(BCS.U64, AMOUNT_ONE + 1).toBytes(),
]).toString();

console.log('wrong leaf', tree.verify(proof, wrongLeaf, root)); // false
console.log('right leaf', tree.verify(proof, leaf.toString(), root)); // true
