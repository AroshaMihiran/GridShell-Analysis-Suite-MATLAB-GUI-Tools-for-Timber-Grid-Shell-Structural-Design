function L0=GetL(NODE,BARS)
L0=sqrt((NODE(BARS(:,2),1)-NODE(BARS(:,1),1)).^2+(NODE(BARS(:,2),2)-NODE(BARS(:,1),2)).^2+(NODE(BARS(:,2),3)-NODE(BARS(:,1),3)).^2);
end


