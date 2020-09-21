import java.util.LinkedList;
import java.util.Queue;

class Solution {
       public static int solution(String originalStr) {
        int oriStrLen = originalStr.length();
        int min = oriStrLen;
        Queue<String> q = new LinkedList<>();

        for(int i=1; i<=oriStrLen/2; i++) {
            String newStr = "";
            String prevStr = "";
            int cnt = 1;

            for(int j=0; j<oriStrLen; j+=i) {
                int scanSize = i;
                int from = j;
                int to = from+scanSize;

                if(to > oriStrLen) {
                    q.add(originalStr.substring(from));
                    break;
                } else {
                    q.add(originalStr.substring(from, to));
                }
            }

            while(!q.isEmpty()) {
                String currStr = q.poll();
                boolean isLast = q.isEmpty() ? true : false;

                if(currStr.equals(prevStr)) {
                    cnt++;
                    if(isLast) {
                        newStr+= Integer.toString(cnt) + currStr;
                    }
                } else {
                   String preFix = (cnt==1) ? "" : Integer.toString(cnt);
                   String addStr = isLast ? (preFix+prevStr+currStr) : (preFix+prevStr);
                   newStr+=addStr;
                   cnt = 1;
                }

                prevStr = currStr;
            }

            min = newStr.length() > min ? min : newStr.length();
        }

        return min;
    }
}
