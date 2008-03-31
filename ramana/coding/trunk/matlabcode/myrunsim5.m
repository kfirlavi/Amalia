% with packet arrivals, routing delay, extra packets metrics
% with circular queue operations

%clear;
%global rr;
%global bb;

% fields in the node structurr
%r

%global ratetx;
%global blocksize;

NID=1;
DATA=2;
FRONT=3;
REAR=4;
QSIZE=5; % used in q structure only
TBUFF=6; % used in q structure only
TREAR=7; % used in q structure only
QSTATS=8;


TOTAL=5; % used in vq structure only
TIME=6; % used in vq structure only
REMAIN=7; % used in vq structure only
COPIED=8; % used in vq structure only




% fields in the packet
% packet format [flowid saddr daddr blockId packetid timestamp hcount isextrapart bitmap_of_encoded_packets] 
FLOWID=1;
SRCBIT=2;
DSTBIT=3;
BLKID=4;
PAKID=5; % 5th field in the packet
TIMESTAMP=6; 
RECVTIME=7; % maximum permitted hops to cross
ISEXTRA=8; % is extra/redudant part started



% fields in the flist structure
SRC=1;
DST=2;
DELAY=3;
EXTRA=4;
TOTALPKTS =5;
BSTATS=6;

clear flist vq q;

% flist{1}{SRC}=1;
% flist{1}{DST}=5;
%
% % case 1
%
% n=5;
% numFlows=1;
%
% %topology
% P= [0 1 0 0 0;
%     1 0 1 0 0;
%     0 0 0 1 1;
%     0 1 0 0 0;
%     0 0 1 0 0;];
%
% PS=P*2;    % rate matrix
% sink=n;
% PS(3,sink)=1;

% case 2
%n = 10;
%P=[ 0 1 0 0 0 0 0 0 0 0;
%    1 0 1 0 0 0 0 1 1 0;
%    0 1 0 1 0 0 0 0 0 0;
%    0 0 0 0 0 0 0 0 1 0;
%    0 1 1 0 0 1 0 1 0 0;
%    0 0 0 0 0 0 1 0 0 0;
%    0 0 0 0 0 0 0 0 0 0;
%    0 1 0 0 0 0 0 0 0 1;
%    0 0 0 0 1 0 0 0 0 0;
%    0 0 0 0 1 0 0 0 0 0; ];
%
%PS=[ 0 2 0 0 0 0 0 0 0 0;
%    2 0 2 0 0 0 0 2 1 0;
%    0 2 0 1 0 0 0 0 0 0;
%    0 0 0 0 0 0 0 0 1 0;
%    0 10 10 0 0 2 0 10 0 0;
%    0 0 0 0 0 0 2 0 0 0;
%    0 0 0 0 0 0 0 0 0 0;
%    0 2 0 0 0 0 0 0 0 1;
%    0 0 0 0 1 0 0 0 0 0;
%    0 0 0 0 1 0 0 0 0 0; ];

% senders   = [ 1 1 4 5 8 ];
% receivers = [ 7 4 6 1 3 ];

%P = [ 0 1 0 0 0 0;
%      1 0 1 0 1 0;
%      0 0 0 1 0 0;
%      0 1 0 0 0 1;
%      0 0 0 1 0 0;
%      0 0 0 1 0 0  ];
%
%PS =[ 0 2 0 0 0 0;
%      10 0 1 0 1 0;
%      0 0 0 1 0 0;
%      0 10 0 0 0 2;
%      0 0 0 1 0 0;
%      0 0 0 2 0 0  ];
%n=6;
%
%senders   = [ 1 6 ]; %9 5 8 ];
%receivers = [ 6 1 ]; %6 4 3 ];

P = [ 0 1 0 0 0;
      0 0 1 0 0;
      0 0 0 1 1;
      0 1 0 0 0;
      0 0 0 0 0 ];

PS = [ 0 10 0 0 0;
      0 0 8 0 0;
      0 0 0 8 1;
      0 8 0 0 0;
      0 0 0 0 0 ];

n=5;
numFlows=1;
senders = 1;
receivers = 5;
bSize=blocksize; % block size
maxRows=300;
maxBsize=bSize+8; 
mapstart=9; % bitmap in the packet starts from this field
nodes = n;
maxPackets=ones(1,numFlows)*50000;

for i=1:numFlows,
    flist{i}{SRC} = senders(i);
    flist{i}{DST} = receivers(i);
    flist{i}{DELAY}=[];
    flist{i}{EXTRA}=0;
    flist{i}{TOTALPKTS}=[]; %zeros(1,(maxPackets(i)/bSize));
    flist{i}{BSTATS}=[]; % decoding times
  % flist{i}=zeros(nodes,2000); %zeros(1,(maxPackets(i)/bSize));
end


%global maxQsize;
%maxQsize=maxRows;

% notes: queue operatiosn stuff
% empty queue: front == rear
% full queue:  front == addone(rear)
% insert at rear then rear = addone(rear)
% delete fron front then front = addone(front);

MQ = zeros(nodes,numFlows);
MW = zeros(1,nodes);
MT = zeros(nodes,numFlows);

complete=zeros(1,numFlows);
acked=ones(1,numFlows);
sent=zeros(1,numFlows);
received=zeros(1,numFlows);
blockSent=zeros(1,numFlows);
blockId = zeros(1,numFlows);
maxId=ones(1,numFlows);
copied=ones(1,numFlows);
done_all=0;

% DATA structure at each node
for i=1:nodes,
    q{i}{NID}=i;
    vq{i}{NID}=i;
    for fl=1:numFlows,
        q{i,fl}{DATA}=zeros(maxRows,maxBsize);
        q{i,fl}{TBUFF}=zeros(bSize,maxBsize);
        q{i,fl}{FRONT}=1; % FRONT pointer
        q{i,fl}{REAR}=1;  % REAR pointer
        q{i,fl}{QSIZE}=0;
        q{i,fl}{QSTATS}=[]; % queue sizes at each time step
        
        vq{i,fl}{FRONT}=1;
        vq{i,fl}{REAR}=1;
        vq{i,fl}{DATA}=zeros(maxRows,maxBsize);
        vq{i,fl}{TOTAL}=0;
        vq{i,fl}{TIME}=zeros(1,maxPackets(fl));
	vq{i,fl}{REMAIN} = [];
	vq{i,fl}{COPIED} = [];
        
    end
end

tstep=1;

while ~done_all,

    % check for each source and fill the virtual queue based on the rate
    rate = ratetx; %0.5; %0.5;
    for fl=1:numFlows,
        s=flist{fl}{SRC};
        while (rand < rate/(rate+1))
            if (vq{s,fl}{TOTAL} > maxPackets(fl))
                break
            else              
                vq{s,fl}{REAR}=vq{s,fl}{REAR}+1;
                vq{s,fl}{TOTAL}=vq{s,fl}{TOTAL}+1;
                vq{s,fl}{TIME}(vq{s,fl}{TOTAL})=tstep;
            end
        end
    end

    % check a block for any flow has been acked or needs to push some
    % redundant packets

    for fl=1:numFlows,

        s=flist{fl}{SRC};
        d=flist{fl}{DST};

        % if acked then reset REAR pointer
        if (acked(fl))
		intransit=0;
		for nn=2:1:4,
 			intransit = intransit + q{nn,1}{QSIZE};
		end
% 		if(sent-received-intransit == 0)
 	%		fprintf('\nsent: %d received: %d intrans %d diff: %d',sent,received,intransit, sent-received-intransit);
% 		end
		sent=zeros(1,numFlows);
		received=zeros(1,numFlows);
            maxId(fl)=q{s,fl}{DATA}(q{s,fl}{REAR},PAKID);
            q{s,fl}{REAR} = 1;
            q{s,fl}{FRONT} = 1;
            q{s,fl}{QSIZE} = 0;
            	acked(fl) = 0;
            for nn=1:nodes,
                q{nn,fl}{DATA}=zeros(maxRows,maxBsize); %bit map
		q{nn,fl}{TBUFF}=zeros(bSize,maxBsize);
		q{nn,fl}{TREAR}=1; % just rear pointer, no need to have front pointer
                q{nn,fl}{FRONT}=1; % FRONT pointer
                q{nn,fl}{REAR}=1; % REAR pointer
                q{nn,fl}{QSIZE}=0;
            end
	    
            if(blockSent(fl)*bSize == maxPackets(fl))
                complete(fl) = 1;
            end;
            blockSent(fl) = blockSent(fl) + 1;
        end

        if (q{s,fl}{REAR} <= bSize && complete(fl) ~= 1)
            vq{s,fl}{REMAIN} = [vq{s,fl}{REMAIN},vq{s,fl}{REAR}];
            %need to push as many packets as possible from vq to q
% 	    if ( vq{s,fl}{REAR} ~= vq{s,fl}{FRONT} )
            	count = min(vq{s,fl}{REAR} - vq{s,fl}{FRONT}, bSize+1 - q{s,fl}{REAR});
 %	    else
  %           	count = min(0, bSize+1 - q{s,fl}{REAR});
 %	    end
	    
            vq{s,fl}{REAR} = vq{s,fl}{REAR} - count;            
	    vq{s,fl}{COPIED} = [vq{s,fl}{COPIED},count];
	    %vq{s,fl}{REMAIN} = [vq{s,fl}{REMAIN},count];
            for x1=1:count
                rr1=q{s,fl}{REAR};
                mesg = zeros(1,bSize);
                mesg(rr1)=1;
                tstamp=vq{s,fl}{TIME}(copied(fl));
                mesg1 =[fl s d blockSent(fl) maxId(fl)+rr1 tstamp 0 0 mesg];
                %mesg1 =[fl s d blockSent(fl) maxId(fl)+rr1 tstep 0 0 mesg];
                q{s,fl}{DATA}(rr1,:) = mesg1;
                q{s,fl}{REAR} = rr1 + 1;
                copied(fl)=copied(fl)+1;
            end
            if (q{s,fl}{REAR} == bSize+1)
                extra=rand(maxRows-bSize,bSize);
                ii=find(extra>=0.5); extra(ii)=1;
                ii=find(extra<0.5); extra(ii)=0;
                a=[ones(1,bSize);extra];
                b=[];
                for ix=1:max(size(a)),
                    b=[b; fl s d blockSent(fl) maxId(fl)+bSize+ix 0 0 1];
                end
                c = [b a]; % extra part is ready, now append with the queue
                temp=[q{s,fl}{DATA}(1:bSize,:);c];
                q{s,fl}{DATA} = temp;
                q{s,fl}{REAR} =  maxRows;
            end
        end
        q{s,fl}{QSIZE} = q{s,fl}{REAR} - q{s,fl}{FRONT};
    end


    W = zeros(1,nodes);
    for n = 1:nodes,
        % check if this is a sink, if so drain the packet
        for fl = 1:numFlows,
            d=flist{fl}{DST};
            s=flist{fl}{SRC};
            if ( n ~= d )
                continue;
            else
                %cqsize=q{n,fl}{REAR} - q{n,fl}{FRONT};
                cqsize = q{n,fl}{QSIZE};
                if (cqsize > 0)
                    % drain out this packet as this is the dest
                    % check if it can decode use matrix inversion
                    % copy q contents into vbuff

		    received(fl) = received(fl) + cqsize;
                    from=vq{n,fl}{REAR};
                    to=vq{n,fl}{REAR}+cqsize-1; % -1 because rear points alway the next empty location
                    from1=q{n,fl}{FRONT};
                    to1=  from1+cqsize-1;            %q{n,fl}{REAR}-1;
                    dat=q{n,fl}{DATA}(from1:to1,:);
                    curblk=q{n,fl}{DATA}(from1, BLKID);
                    W(n)=W(n)+cqsize;
                    q{n,fl}{FRONT}=from1+cqsize;       % reset the main buffer
                    q{n,fl}{QSIZE} = 0;
		    %fprintf('\n received');
                    % do not allow copying from previous blocks
                    if ( curblk ~= blockId(fl) )
                        dat(1:end,RECVTIME)=tstep;
                        vq{n,fl}{DATA}(from:to,:)=dat; 
                        vq{n,fl}{REAR}=vq{n,fl}{REAR}+cqsize;
                    else
                        % send an ACK for the block
                        %isack=1;
                        %ackmesg = [ fl d s blockId(fl) 1 isack zeros(1:bSize) ]
                        %q{n,fl}{DATA}(q{n,fl}{REAR},:) = ackmesg;
                        %q{n,fl}{REAR}= q{n,fl}{REAR}+1;
                    end
                 
		    % Time at which the decoding
		    % Number of extra packet for decoding  

                    %check for rank using vbuff
                    if(vq{n,fl}{REAR}-1 >= bSize)
                        a1=logical(vq{n,fl}{DATA}(1:vq{n,fl}{REAR}-1,mapstart:end));
                        if (RankMod2(transpose(a1(1:vq{n,fl}{REAR}-1,:)))==bSize)
                            %decoded successfully
                            acked(fl)=1;
                            a9=vq{n,fl}{DATA}(1:vq{n,fl}{REAR}-1,mapstart:end);
                            amaster=vq{n,fl}{DATA}(1:vq{n,fl}{REAR}-1,:); % just backup
                            sentTimes=vq{n,fl}{DATA}(1:vq{n,fl}{REAR}-1,TIME);
                            recvTimes=vq{n,fl}{DATA}(1:vq{n,fl}{REAR}-1,RECVTIME);
                            new3; % compute decoding delays
                            xtemp=(recvTimes - sentTimes); % routing delays
			    xtemp=(xtemp'+rowdelay); % add routing and decoding delays
                            flist{fl}{DELAY} = [flist{fl}{DELAY},xtemp];
                            flist{fl}{TOTALPKTS} = [flist{fl}{TOTALPKTS},max(size(a9))];
                            blockId(fl)=vq{n,fl}{DATA}(vq{n,fl}{REAR}-1,BLKID);
                            vq{n,fl}{REAR}=1;
                            vq{n,fl}{FRONT}=1;
			    flist{fl}{BSTATS} = [flist{fl}{BSTATS},tstep];
                            % send an ACK for the block
                            %isack=1;
                            %ackmesg = [ fl d s blockId(fl) 1 isack zeros(1:bSize) ]
                            %q{n,fl}{DATA}(q{n,fl}{REAR},:) = ackmesg;
                            %q{n,fl}{REAR}= q{n,fl}{REAR}+1;
                        end
                    end

                end
            end
        end

        % for all other nodes, do flow scheduling and routing
        % check the flows and findout the flow to be scheduled
        % then check the neighbours and find the next hop

        ii=find(P(n,:)>0); % get all the neighbours
        ii=ii(randperm(length(ii))); % jumble things up to create random tie-break

        cost=0;
        inx=0;
        index=zeros(1,numFlows);
        ngqsize=zeros(numFlows,nodes);

        % for each flow it has
        for fl=1:numFlows,
            %cqsize(fl)=q{n,fl}{REAR} - q{n,fl}{FRONT};
            cqsize(fl)=q{n,fl}{QSIZE};
            if (cqsize(fl) > 0)
                cost(fl)=0;
                index(fl)=0;
                for ng=1:length(ii),
                    %compute the cost for this flow too
                    %ngcqsize(fl,ii(ng)) = q{ii(ng),fl}{REAR} - q{ii(ng),fl}{FRONT};
                    %ccost=(cqsize(fl) - ngcqsize(fl,ii(ng)))*PS(n,ii(ng));
                    ccost=(cqsize(fl) - q{ii(ng),fl}{QSIZE})*PS(n,ii(ng));
                    if(ccost > cost(fl))
                        cost(fl)=ccost;
                        index(fl)=ii(ng);
                    end
                end
            end
        end

        %select flow
        ng=0; fl=0; inx=0;
        [cst,fl]=max(cost);
        inx=index(fl);

        % schedule flow fl and next hop is inx
        if (cst > 0 && inx ~= 0)
            % burstSize = min (PS(n,inx), q{n,fl}{REAR} - q{n,fl}{FRONT});
            burstSize = min (PS(n,inx), q{n,fl}{QSIZE});
            rr1=q{inx,fl}{REAR};
            ff1=q{n,fl}{FRONT};
            %s1=q{inx,fl}{DATA}(rr1,SRCBIT);
            %d1=q{inx,fl}{DATA}(rr1,DSTBIT);
            for kx=1:burstSize,
                mesg=q{n,fl}{DATA}(ff1,:);
                if(mesg(SRCBIT) == inx) % do not send the packet to its originator, simply drop this
                    ff1=ff1+1;
                    continue;
                end
                if(mesg(SRCBIT) == n && mesg(ISEXTRA) == 1)   
                    flist{fl}{EXTRA}=flist{fl}{EXTRA} + 1;
                    %fprintf('fl: %d extrapkts: %d n: %d \n',fl,flist{fl}{EXTRA},n);
                    mesg(TIME)=tstep;
                end
                if(mesg(SRCBIT) == n)
			sent(fl) = sent(fl)+1;
		end
                q{inx,fl}{DATA}(rr1,:)= mesg; %q{n,fl}{DATA}(ff1,:);
               % fprintf('flow: %d from %d to %d pakid: %d size1: %d size2: %d s: %d d: %d busrtsize: %d\n',fl, n,inx,q{n,fl}{DATA}(ff1,5), q{n,fl}{REAR}-q{n,fl}{FRONT}, q{inx,fl}{REAR} - q{inx,fl}{FRONT},s1,d1, burstSize);
                rr1=rr1+1;
                ff1=ff1+1;
                W(n)=W(n)+1;
            end
            q{n,fl}{FRONT}=ff1;
            q{inx,fl}{REAR}=rr1;
        end
    end
    for kk=1:nodes
        for fl=1:numFlows,
            q{kk,fl}{QSIZE} = (q{kk,fl}{REAR} - q{kk,fl}{FRONT});
	    q{kk,fl}{QSTATS} = [q{kk,fl}{QSTATS},q{kk,fl}{QSIZE}];
              %if (q{kk,fl}{FRONT} == q{kk,fl}{REAR} && flist{fl}{SRC} ~= kk)
              if (flist{fl}{SRC} ~= kk)
			mesg2=zeros(maxRows,maxBsize);
			if (q{kk,fl}{FRONT} ~= q{kk,fl}{REAR})
                    		mesg2 = q{kk,fl}{DATA}(q{kk,fl}{FRONT}:q{kk,fl}{REAR}-1,:);
                       		q{kk,fl}{REAR}= q{kk,fl}{REAR} - q{kk,fl}{FRONT} + 1;
                       		q{kk,fl}{DATA}=mesg2;
                                q{kk,fl}{FRONT}=1;
		       	%	fprintf('\n time: %d node: %d',tstep,kk );
			end
               end
        end
    end
    MW = MW+W;
    if(sum(complete) == numFlows)
        done_all=1;
        continue;
    end
    tstep = tstep + 1;
end
%tstep
%fprintf('Work - opportunistic ')
%MW
for fl=1:numFlows,
	nblocks=maxPackets(fl)/bSize;
	MQL{fl} = zeros(nblocks,nodes);
end
for fl=1:numFlows,
	fprintf('\n bsize: %d rate: %d extra: %d meand: %f stdd: %f mean blocksize: %f',bSize, rate, flist{fl}{EXTRA},mean(flist{fl}{DELAY}), std(flist{fl}{DELAY}), mean(flist{fl}{TOTALPKTS}));
	nblocks=maxPackets(fl)/bSize;
	for fl2=1:nblocks,
		dtime=flist{fl}{BSTATS}(fl2);
		for fl3=1:nodes,
			MQL{fl}(fl2,fl3) = q{fl3,fl}{QSTATS}(1,dtime);
		end
	end
end
