// https://www.acmicpc.net/problem/7576

import java.util.*;

class Point {
    int x;
    int y;

    Point(int x, int y) {
        this.x = x;
        this.y = y;
    }
}

public class Main {
    static int[][] tomatoBox;
    static boolean[][] isVisited;
    static int row;
    static int col;

    public static int bfs(List<Point> visitPoints, int day) {
        int[] xDir = {0, 0, 1, -1}; // 동서남북
        int[] yDir = {1, -1,0, 0}; // 동서남북
        List<Point> newVisitPoints = new ArrayList<>();
        int answer = day;

        for(Point p : visitPoints) {
            for(int i=0; i<4; i++) {
                int nextX = p.x + xDir[i];
                int nextY = p.y + yDir[i];
                boolean cond1 = nextX>=0 && nextX<row;
                boolean cond2 = nextY>=0 && nextY<col;

                if(cond1 && cond2) {
                    if(tomatoBox[nextX][nextY]==0 && !isVisited[nextX][nextY]) {
                        isVisited[nextX][nextY] = true;
                        tomatoBox[nextX][nextY] = 1;
                        newVisitPoints.add(new Point(nextX, nextY));
                    }
                }
            }
        }

        if(newVisitPoints.size() > 0) {
            answer = bfs(newVisitPoints, day+1);
        } else {
            for (int i = 0; i < row; i++) {
                for (int j = 0; j < col; j++) {
                    if (tomatoBox[i][j] == 0) {
                        answer = -1;
                        break;
                    }
                }
            }
        }

        return answer;
    }

    public static void main(String[] args) {
        Scanner sc = new Scanner(System.in);
        List<Point> visitPoints = new ArrayList<>();

        col = sc.nextInt();
        row = sc.nextInt();
        tomatoBox = new int[row][col];
        isVisited = new boolean[row][col];

        for(int i=0; i<row; i++) {
            for(int j=0; j<col; j++) {
                int tomatoStatus = sc.nextInt();
                tomatoBox[i][j] = tomatoStatus;
                isVisited[i][j] = false;

                if(tomatoStatus==1) {
                    visitPoints.add(new Point(i,j));
                    isVisited[i][j] = true;
                }
            }
        }
        System.out.print(bfs(visitPoints, 0));
    }
}
