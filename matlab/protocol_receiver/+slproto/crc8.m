function r = crc8(bits)
%CRC8 0x4D，多项式x^8+x^6+x^3+x^2+1；初值FF，MSB先行，无反射/末异或。
bits=bits(:);assert(all(bits==0|bits==1));r=uint16(255);
for n=1:numel(bits)
    feedback=xor(bitget(r,8)~=0,logical(bits(n)));r=bitand(bitshift(r,1),255);
    if feedback,r=bitxor(r,77);end
end
r=double(r);
end
